library(claudeCodeR)

message("=== Testing Server Initialization with Logs ===\n")

auth_config <- detect_auth_method()
message("Auth method: ", auth_config$method)
message("Permission mode: ", auth_config$permission_mode, "\n")

working_dir <- get_working_dir()
message("Working dir: ", working_dir, "\n")

message("Starting SDK server...")
sdk_process <- start_sdk_server(working_dir, auth_config, port = 8765)
message("SDK server PID: ", sdk_process$get_pid(), "\n")

Sys.sleep(3)

message("Reading server stderr...")
stderr_lines <- sdk_process$read_error_lines()
if (length(stderr_lines) > 0) {
  message("=== SERVER STDERR ===")
  for (line in stderr_lines) {
    message(line)
  }
  message("=== END STDERR ===\n")
}

message("Checking server health...")
base_url <- "http://127.0.0.1:8765"
health <- check_health(ClaudeSDKClient(base_url))
message("Health check: ", health$status, "\n")

if (health$status == "ok" || health$status == "not_initialized") {
  message("Attempting to initialize session...")
  client <- ClaudeSDKClient(base_url)

  result <- tryCatch({
    client <- initialize_session(client, working_dir, auth_config)
    message("SUCCESS: Session initialized!")
    client
  }, error = function(e) {
    message("ERROR during initialization: ", e$message)

    message("\nReading stderr after error...")
    stderr_lines <- sdk_process$read_error_lines()
    if (length(stderr_lines) > 0) {
      message("=== SERVER STDERR ===")
      for (line in stderr_lines) {
        message(line)
      }
      message("=== END STDERR ===")
    }
    NULL
  })

  if (!is.null(result)) {
    shutdown_session(result)
  }
}

message("\nKilling server...")
sdk_process$kill()
message("Done!")
