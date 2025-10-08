claude_code_addin_bg <- function() {
  if (!rstudioapi::isAvailable()) {
    stop("This addin requires RStudio")
  }

  auth_config <- detect_auth_method()

  if (is.null(auth_config)) {
    rstudioapi::showDialog(
      "Authentication Required",
      "No authentication method found.\n\nPlease use one of:\n\n1. Claude subscription: Run 'claude auth login' in terminal\n2. API key: Set ANTHROPIC_API_KEY environment variable\n3. AWS Bedrock: Set CLAUDE_CODE_USE_BEDROCK=1\n\nSee README.md for setup instructions."
    )
    return(invisible(NULL))
  }

  if (auth_config$method == "bedrock") {
    if (!validate_aws_credentials(auth_config)) {
      message("AWS credentials not valid or expired")

      response <- rstudioapi::showQuestion(
        "AWS Login Required",
        "AWS credentials are not valid. Would you like to login via AWS SSO?",
        ok = "Login",
        cancel = "Cancel"
      )

      if (response) {
        tryCatch({
          prompt_aws_sso_login(auth_config$aws_profile)
        }, error = function(e) {
          rstudioapi::showDialog(
            "Login Failed",
            paste("AWS SSO login failed:", e$message)
          )
          return(invisible(NULL))
        })
      } else {
        return(invisible(NULL))
      }
    }
  }

  working_dir <- get_working_dir()
  port <- 8765
  app_port <- 3838

  killed_ports <- kill_processes_on_ports(c(port, app_port))
  if (killed_ports > 0) {
    message("Cleaned up ", killed_ports, " existing server process(es)")
    Sys.sleep(1)
  }

  message("Starting Claude Code in background...")

  bg_process <- callr::r_bg(
    func = function(auth_config, working_dir, sdk_port, app_port) {
      library(claudeCodeR)
      library(shiny)

      base_url <- paste0("http://127.0.0.1:", sdk_port)

      sdk_process <- start_sdk_server(working_dir, auth_config, port = sdk_port)

      if (!wait_for_server(base_url, timeout = 10)) {
        sdk_process$kill()
        stop("SDK server failed to start")
      }

      message("SDK server ready, starting Shiny app on port ", app_port)

      app <- shinyApp(
        ui = claude_sdk_ui(auth_config),
        server = claude_sdk_server_factory(base_url, working_dir, auth_config, sdk_process),
        options = list(
          port = app_port,
          host = "127.0.0.1",
          launch.browser = FALSE
        )
      )

      on.exit({
        message("Shutting down SDK server...")
        sdk_process$kill()
      })

      runApp(app)
    },
    args = list(
      auth_config = auth_config,
      working_dir = working_dir,
      sdk_port = port,
      app_port = app_port
    ),
    supervise = TRUE,
    stdout = "|",
    stderr = "|"
  )

  Sys.sleep(3)

  if (!bg_process$is_alive()) {
    stderr_output <- bg_process$read_error()
    stdout_output <- bg_process$read_output()
    stop("Background process failed:\nSTDERR: ", stderr_output, "\nSTDOUT: ", stdout_output)
  }

  app_url <- paste0("http://127.0.0.1:", app_port)

  if (!wait_for_app(app_url, timeout = 10)) {
    stderr_output <- bg_process$read_error()
    stdout_output <- bg_process$read_output()
    bg_process$kill()
    stop("Shiny app failed to start.\nSTDERR: ", stderr_output, "\nSTDOUT: ", stdout_output)
  }

  message("Claude Code is ready!")
  message("Opening browser to: ", app_url)
  message("The app is running in background. Use claude_code_stop() to stop it.")

  utils::browseURL(app_url)

  .GlobalEnv$.claude_code_process <- bg_process

  invisible(bg_process)
}

claude_code_stop <- function() {
  stopped_anything <- FALSE

  if (exists(".claude_code_process", envir = .GlobalEnv)) {
    proc <- get(".claude_code_process", envir = .GlobalEnv)
    if (proc$is_alive()) {
      message("Stopping Claude Code background process...")
      proc$kill()
      stopped_anything <- TRUE
    }
    rm(".claude_code_process", envir = .GlobalEnv)
  }

  killed_ports <- kill_processes_on_ports(c(8765, 3838))
  killed_callr <- kill_callr_processes()

  if (killed_ports > 0) {
    message("Killed ", killed_ports, " orphaned server process(es)")
    stopped_anything <- TRUE
  }

  if (killed_callr > 0) {
    message("Killed ", killed_callr, " stuck background process(es)")
    stopped_anything <- TRUE
  }

  if (stopped_anything) {
    message("Claude Code stopped")
  } else {
    message("No Claude Code processes found")
  }

  invisible(NULL)
}

claude_code_reset <- function() {
  message("Resetting Claude Code (killing all related processes)...")
  claude_code_stop()
  message("Reset complete. You can now restart Claude Code.")
  invisible(NULL)
}

kill_processes_on_ports <- function(ports) {
  killed_count <- 0

  for (port in ports) {
    result <- tryCatch({
      system(paste0("lsof -ti :", port, " | xargs kill -9 2>/dev/null"),
             ignore.stdout = TRUE,
             ignore.stderr = TRUE)
      0
    }, error = function(e) 1)

    if (result == 0) {
      killed_count <- killed_count + 1
    }
  }

  killed_count
}

kill_callr_processes <- function() {
  result <- tryCatch({
    pids_output <- system("ps aux | grep 'callr-scr' | grep -v grep | awk '{print $2}'",
                          intern = TRUE, ignore.stderr = TRUE)

    if (length(pids_output) > 0 && nchar(pids_output[1]) > 0) {
      pids <- trimws(pids_output)
      system(paste0("kill -9 ", paste(pids, collapse = " "), " 2>/dev/null"),
             ignore.stdout = TRUE, ignore.stderr = TRUE)
      return(length(pids))
    }
    0
  }, error = function(e) 0)

  result
}

wait_for_app <- function(url, timeout = 10) {
  start_time <- Sys.time()

  while (as.numeric(difftime(Sys.time(), start_time, units = "secs")) < timeout) {
    tryCatch({
      response <- httr::GET(url, httr::timeout(1))
      if (!httr::http_error(response)) {
        return(TRUE)
      }
    }, error = function(e) {
    })

    Sys.sleep(0.5)
  }

  FALSE
}
