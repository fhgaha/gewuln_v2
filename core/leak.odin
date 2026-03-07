package core

import "base:runtime"
import "core:fmt"
import "core:mem"

Tracking_Allocation :: struct {
	memory:   rawptr,
	size:     int,
	location: runtime.Source_Code_Location,
}

Tracking_Allocator_Data :: struct {
	backing: mem.Allocator,
	allocs:  map[rawptr]Tracking_Allocation,
}

/*
Example:

main :: proc() {
    tracking_data := Tracking_Allocator_Data{
        backing = context.allocator,
        allocs = make(map[rawptr]Tracking_Allocation, context.allocator), // use same backing for map
    }
    defer delete(tracking_data.allocs) // cleanup map itself
    
    context.allocator = tracking_allocator(&tracking_data)
    defer check_leaks(tracking_data)

    ptr := new(int)   // this allocation will be tracked
    // forget to free(ptr) -> leak will be reported
    _ = ptr
}
*/

tracking_allocator :: proc(data: ^Tracking_Allocator_Data) -> mem.Allocator {
	return mem.Allocator {
		data = data,
		procedure = proc(
			allocator_data: rawptr,
			mode: mem.Allocator_Mode,
			size, alignment: int,
			old_memory: rawptr,
			old_size: int,
			loc: runtime.Source_Code_Location = #caller_location,
		) -> (
			result: []byte,
			err: mem.Allocator_Error,
		) {
			data := cast(^Tracking_Allocator_Data)allocator_data

			// Call the backing allocator
			result, err = data.backing.procedure(
				data.backing.data,
				mode,
				size,
				alignment,
				old_memory,
				old_size,
				loc,
			)

			// If the operation failed, nothing to track
			if err != nil {
				return
			}

			// For map operations, use the backing allocator to avoid recursion
			context.allocator = data.backing
			defer context.allocator = tracking_allocator(data)

			#partial switch mode {
			case .Alloc, .Alloc_Non_Zeroed:
				if result != nil {
					ptr := raw_data(result)
					data.allocs[ptr] = Tracking_Allocation{ptr, size, loc}
				}
			case .Free:
				delete_key(&data.allocs, old_memory)
			case .Free_All:
				clear(&data.allocs)
			case .Resize, .Resize_Non_Zeroed:
				if old_memory != nil {
					delete_key(&data.allocs, old_memory)
				}
				if result != nil {
					ptr := raw_data(result)
					data.allocs[ptr] = Tracking_Allocation{ptr, size, loc}
				}
			case .Query_Features, .Query_Info:
			// No allocation/free, nothing to track
			}
			return
		},
	}
}

check_leaks :: proc(data: Tracking_Allocator_Data) {
	fmt.println("\n=== Leak Report Started ===")
	for _, alloc in data.allocs {
		fmt.printf(
			"LEAK: %p of size %d allocated at %s:%d in %s\n",
			alloc.memory,
			alloc.size,
			alloc.location.file_path,
			alloc.location.line,
			alloc.location.procedure,
		)
	}
	if len(data.allocs) == 0 {
		fmt.println("No leaks detected.")
	}
	fmt.println("\n=== Leak Report Ended ===")
}
