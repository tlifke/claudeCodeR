claude_code_addin_bg <- function() {
  if (!rstudioapi::isAvailable()) {
    stop("This addin requires RStudio")
  }

  kill_existing_sdk_servers()

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
  app_port <- 3838  # Port for Shiny app

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
    stop("Background process failed: ", stderr_output)
  }

  app_url <- paste0("http://127.0.0.1:", app_port)

  if (!wait_for_app(app_url, timeout = 10)) {
    bg_process$kill()
    stop("Shiny app failed to start")
  }

  message("Claude Code is ready!")
  message("Opening browser to: ", app_url)
  message("The app is running in background. Use claude_code_stop() to stop it.")

  utils::browseURL(app_url)

  .GlobalEnv$.claude_code_process <- bg_process

  invisible(bg_process)
}

claude_code_stop <- function() {
  if (exists(".claude_code_process", envir = .GlobalEnv)) {
    proc <- get(".claude_code_process", envir = .GlobalEnv)
    if (proc$is_alive()) {
      message("Stopping Claude Code background process...")
      proc$kill()
      rm(".claude_code_process", envir = .GlobalEnv)
      message("Claude Code stopped")
    } else {
      message("Claude Code process is not running")
    }
  } else {
    message("No Claude Code process found")
  }
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
