library(claudeCodeR)

message("=== Starting Permission Test (Blocking Mode) ===\n")

message("Step 1: Detecting authentication...")
auth_config <- detect_auth_method()
if (is.null(auth_config)) {
  stop("No authentication method found!")
}
message("Auth method: ", auth_config$method)
message("Permission mode: ", auth_config$permission_mode, "\n")

message("Step 2: Getting working directory...")
working_dir <- get_working_dir()
message("Working dir: ", working_dir, "\n")

message("Step 3: Starting SDK server...")
sdk_process <- start_sdk_server(working_dir, auth_config, port = 8765)
message("SDK server started (PID: ", sdk_process$get_pid(), ")")

Sys.sleep(2)

message("\n=== Python Server Stderr ===")
stderr_lines <- sdk_process$read_error_lines()
for (line in stderr_lines) {
  message(line)
}
message("=== End Server Stderr ===\n")

base_url <- "http://127.0.0.1:8765"

message("Step 4: Waiting for server to be ready...")
if (!wait_for_server(base_url, timeout = 10)) {
  sdk_process$kill()
  stop("Server failed to start")
}
message("Server ready!\n")

message("Step 5: Creating SDK client...")
client <- ClaudeSDKClient(base_url)

message("Step 6: Initializing session...")
client <- initialize_session(client, working_dir, auth_config)
message("Session initialized!\n")

message("Step 7: Sending query with permission callback...")
message("Query: 'create a file named test_permission_file.txt with the content hello world'\n")

permission_requests <- list()

query_streaming(
  client,
  prompt = "create a file named test_permission_file.txt with the content 'hello world from permissions test'",
  context = NULL,
  on_text = function(text) {
    cat("[TEXT] ", text, "\n", sep = "")
  },
  on_permission = function(request_id, tool_name, input_data) {
    message("\n==============================================")
    message("[PERMISSION REQUEST RECEIVED IN R!]")
    message("Request ID: ", request_id)
    message("Tool Name: ", tool_name)
    message("Input Data: ", jsonlite::toJSON(input_data, auto_unbox = TRUE, pretty = TRUE))
    message("==============================================\n")

    permission_requests[[request_id]] <<- list(
      tool_name = tool_name,
      input = input_data
    )

    user_input <- readline(prompt = "Approve this permission? (y/n): ")
    user_input <- tolower(trimws(user_input))

    if (user_input == "") {
      message("Empty input received, defaulting to DENY")
      approved <- FALSE
    } else {
      approved <- user_input == "y"
    }

    message("User typed: '", user_input, "'")
    message("Sending approval response: ", approved)
    approve_permission(client, request_id, approved)
  },
  on_complete = function() {
    message("\n[COMPLETE] Query finished!")
  },
  on_error = function(error_message, error_type) {
    message("\n[ERROR] ", error_type, ": ", error_message)
  }
)

message("\n=== Test Complete ===")
message("Total permission requests received: ", length(permission_requests))

message("\n=== Final Python Server Stderr ===")
stderr_lines <- sdk_process$read_error_lines()
for (line in stderr_lines) {
  message(line)
}
message("=== End Server Stderr ===")

message("\nShutting down...")
shutdown_session(client)
sdk_process$kill()

if (file.exists("test_permission_file.txt")) {
  message("\nCleaning up test file...")
  file.remove("test_permission_file.txt")
}

message("Done!")
