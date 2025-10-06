start_websocket_proxy <- function(agent = "claude", port = 8766) {
  websocketd_path <- find_websocketd()

  if (!file.exists(websocketd_path)) {
    stop("websocketd not found at: ", websocketd_path)
  }

  config <- get_agent_config(agent)
  if (is.null(config)) {
    stop("Unknown agent: ", agent)
  }

  agent_cmd <- config$command

  message("Starting WebSocket proxy...")
  message("  Agent: ", config$name)
  message("  Command: ", agent_cmd)
  message("  Port: ", port)
  message("  WebSocket URL: ws://localhost:", port)

  agent_cmd_parts <- strsplit(agent_cmd, "\\s+")[[1]]

  proc <- processx::process$new(
    websocketd_path,
    args = c(
      paste0("--port=", port),
      agent_cmd_parts
    ),
    stdout = "|",
    stderr = "|",
    cleanup = TRUE,
    env = c(
      PATH = Sys.getenv("PATH"),
      HOME = Sys.getenv("HOME")
    )
  )

  Sys.sleep(1)

  if (!proc$is_alive()) {
    stderr_output <- tryCatch({
      proc$read_all_error_lines()
    }, error = function(e) {
      c("Could not read stderr")
    })

    stdout_output <- tryCatch({
      proc$read_all_output_lines()
    }, error = function(e) {
      c("Could not read stdout")
    })

    error_msg <- c(
      "WebSocket proxy failed to start.",
      "STDERR:",
      stderr_output,
      "STDOUT:",
      stdout_output
    )

    stop(paste(error_msg, collapse = "\n"))
  }

  message("WebSocket proxy started (PID: ", proc$get_pid(), ")")

  proc
}

check_websocket_ready <- function(port = 8766, timeout = 10) {
  start_time <- Sys.time()

  while (as.numeric(difftime(Sys.time(), start_time, units = "secs")) < timeout) {
    port_open <- tryCatch({
      con <- socketConnection(
        host = "127.0.0.1",
        port = port,
        blocking = FALSE,
        timeout = 1,
        open = "r+"
      )
      close(con)
      TRUE
    }, error = function(e) {
      FALSE
    })

    if (port_open) {
      Sys.sleep(1)
      return(TRUE)
    }

    Sys.sleep(0.5)
  }

  FALSE
}

stop_websocket_proxy <- function(process) {
  if (is.null(process)) {
    return(invisible(NULL))
  }

  if (process$is_alive()) {
    message("Stopping WebSocket proxy (PID: ", process$get_pid(), ")...")
    process$kill()

    Sys.sleep(0.5)

    if (process$is_alive()) {
      message("Force killing proxy...")
      process$kill_tree()
    }

    message("WebSocket proxy stopped")
  }

  invisible(NULL)
}
