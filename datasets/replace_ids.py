#!/usr/bin/env python3
import re
import sys

def change_can_ids_to_zero(input_file, output_file):
    """
    Change all CAN IDs in a CAN log file to 0 (000).
    
    Args:
        input_file: Path to input log file
        output_file: Path to output log file
    """
    try:
        with open(input_file, 'r') as f_in, open(output_file, 'w') as f_out:
            for line in f_in:
                # Match CAN log format: (timestamp) ID#DATA
                # Pattern: (timestamp) HEXID#HEXDATA
                match = re.match(r'(\([0-9.]+\)) ([0-9A-Fa-f]+)(#[0-9A-Fa-f]*)', line)
                
                if match:
                    timestamp = match.group(1)
                    # Replace CAN ID with 0, preserving data
                    data = match.group(3)
                    modified_line = f"{timestamp} 000{data}\n"
                    f_out.write(modified_line)
                else:
                    # If line doesn't match expected format, write as-is
                    f_out.write(line)
        
        print(f"Successfully processed {input_file} -> {output_file}")
        print(f"All CAN IDs changed to 0")
        
    except FileNotFoundError:
        print(f"Error: Input file '{input_file}' not found")
        sys.exit(1)
    except Exception as e:
        print(f"Error processing file: {e}")
        sys.exit(1)

def main():
    if len(sys.argv) != 3:
        print("Usage: python script.py <input_file> <output_file>")
        print("Example: python script.py canlog.txt canlog_modified.txt")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    change_can_ids_to_zero(input_file, output_file)

if __name__ == "__main__":
    main()
