import os
import shutil
import argparse

def convert_sv_to_txt(source_dir, dest_dir, recursive=False):
    """
    Copies .sv files from a source directory to a destination directory,
    changing their extension to .txt.

    Args:
        source_dir (str): The path to the directory to search for .sv files.
        dest_dir (str): The path to the directory where .txt files will be saved.
        recursive (bool): If True, search for files in all subdirectories as well.
    """
    
    # Ensure the destination directory exists, create it if not.
    os.makedirs(dest_dir, exist_ok=True)
    print(f"Destination directory: '{os.path.abspath(dest_dir)}'")
    
    files_copied = 0
    files_found = 0

    if recursive:
        print(f"Starting recursive search in '{os.path.abspath(source_dir)}'...")
        # os.walk is perfect for recursively walking a directory tree
        for dirpath, _, filenames in os.walk(source_dir):
            for filename in filenames:
                if filename.endswith(".sv"):
                    files_found += 1
                    # Construct full path for the source file
                    source_path = os.path.join(dirpath, filename)
                    # Create the new filename
                    new_filename = os.path.splitext(filename)[0] + ".txt"
                    # Construct full path for the destination file
                    destination_path = os.path.join(dest_dir, new_filename)
                    
                    # Copy the file
                    shutil.copy2(source_path, destination_path)
                    print(f"  - Copied '{source_path}' to '{destination_path}'")
                    files_copied += 1
    else:
        print(f"Starting non-recursive search in '{os.path.abspath(source_dir)}'...")
        # os.listdir for a non-recursive (flat) search
        for filename in os.listdir(source_dir):
            if filename.endswith(".sv"):
                files_found += 1
                source_path = os.path.join(source_dir, filename)
                # Check if it's actually a file, not a directory ending in .sv
                if os.path.isfile(source_path):
                    new_filename = os.path.splitext(filename)[0] + ".txt"
                    destination_path = os.path.join(dest_dir, new_filename)
                    
                    # Copy the file
                    shutil.copy2(source_path, destination_path)
                    print(f"  - Copied '{filename}' to '{new_filename}'")
                    files_copied += 1

    print("\n--- Summary ---")
    if files_found == 0:
        print("No .sv files were found.")
    else:
        print(f"Found {files_found} '.sv' files.")
        print(f"Successfully copied and converted {files_copied} files.")

def main():
    """Main function to parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="A script to copy .sv files and change their extension to .txt.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    
    parser.add_argument(
        "source", 
        help="The source directory containing .sv files."
    )
    parser.add_argument(
        "-d", "--destination",
        help="The destination directory to save .txt files.\n"
             "If not provided, files are saved in the source directory."
    )
    parser.add_argument(
        "-r", "--recursive",
        action="store_true", # Makes this a flag, e.g., presence means True
        help="Enable recursive search through all subdirectories."
    )
    
    args = parser.parse_args()
    
    # If destination is not specified, use the source directory
    destination_directory = args.destination if args.destination else args.source
    
    convert_sv_to_txt(args.source, destination_directory, args.recursive)

if __name__ == "__main__":
    main()
    