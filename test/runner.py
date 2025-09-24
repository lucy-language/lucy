import os
import subprocess
import re

def normalize_code(code):
    lines = [line.strip() for line in code.split('\n') if line.strip()]
    return '\n'.join(lines)

def process_ll_content(content, flag = True):
    if (flag):
        lines = content.split('\n')[2:]
    else:
        lines = content.split('\n')
    
    lines = [line.rstrip() for line in lines if line.strip()]
    return '\n'.join(lines)

def process_lc_files(folder_path):
    total_tests  = 0
    passed_tests = 0
    failed_tests = 0

    os.chdir(folder_path)

    for filename in os.listdir('.'):
        if filename.endswith('.lc'):
            total_tests += 1
            file_path   = filename

            with open(file_path, 'r') as f:
                content       = f.read()
                comment_lines = [
                        line.strip()[2:]
                        for line in content.split('\n')
                        if line.strip().startswith('#')]
                
                expected_ir            = '\n'.join(comment_lines)
                processed_expected_ir  = process_ll_content(expected_ir, False)
                expected_ir_normalized = normalize_code(processed_expected_ir)

            ll_filename = filename[:-3] + '.ll'
            try:
                subprocess.run(['lucy', '-c', file_path, '--emit-ir', '--generator'], check=True)

                with open(ll_filename, 'r') as f:
                    generated_ir            = f.read()
                    processed_generated_ir  = process_ll_content(generated_ir)
                    generated_ir_normalized = normalize_code(processed_generated_ir)

                if generated_ir_normalized == expected_ir_normalized:
                    print(f"Test successful: {filename}")
                    passed_tests += 1
                else:
                    print(f"Test failed    : {filename}")
                    print("\033[93mExpected:")
                    print(f"\033[91m{processed_expected_ir}")
                    print("\033[93mGenerated:")
                    print(f"\033[91m{processed_generated_ir}\033[0m")
                    failed_tests += 1

                os.remove(ll_filename)

            except subprocess.CalledProcessError as e:
                print(f"Error running lucy on {filename}: {e}")
                failed_tests += 1
            except FileNotFoundError:
                print(f"Generated .ll file not found for {filename}")
                failed_tests += 1

    print()
    print(f"\033[34mTotal tests: {total_tests}")
    print(f"\033[32mPassed: {passed_tests}")
    print(f"\033[31mFailed: {failed_tests}\033[0m")
    
    return failed_tests == 0

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <test_folder>")
        sys.exit(1)

    folder_path = sys.argv[1]
    if not os.path.isdir(folder_path):
        print(f"Error: {folder_path}, is not a valid directory")
        sys.exit(1)

    success = process_lc_files(folder_path)
    sys.exit(0 if success else 1)
