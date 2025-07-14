# LX_Debug Project

## Purpose
This project is Lexxes' dedicated testing and debugging environment for new functions and features before they get integrated into production projects.

## How it Works
- Use this project to test new functions, experiment with APIs, and debug issues
- When testing is complete and successful, use the command `clean debug` to reset the project
- The `clean debug` command will remove all test functions and restore it to a clean state
- This keeps the testing environment isolated from production code

## Project Structure
- `header.lua` - Plugin metadata and basic validation
- `main.lua` - Main testing area where you implement and test new functions
- `README.md` - This documentation file

## Usage
1. Add your test functions to `main.lua`
2. Test and debug your implementations
3. Once satisfied, copy working functions to their intended production projects
4. Run `clean debug` command to reset this project for next testing session

## Notes
- This is NOT a production project - it's purely for testing
- Don't rely on this code in other projects
- Keep experimental and potentially unstable code here
- Always test thoroughly before moving functions to production 