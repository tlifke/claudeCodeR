claude_code_addin <- function(background = TRUE) {
  if (background) {
    check_mode <- Sys.getenv("CLAUDECODER_MODE", "background")

    if (check_mode == "blocking") {
      claude_code_addin_blocking()
    } else {
      claude_code_addin_bg()
    }
  } else {
    claude_code_addin_blocking()
  }
}

claude_code_addin_blocking <- function() {
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
  base_url <- paste0("http://127.0.0.1:", port)

  message("Starting Claude SDK server...")
  sdk_process <- start_sdk_server(working_dir, auth_config, port = port)

  if (!wait_for_server(base_url, timeout = 10)) {
    sdk_process$kill()
    stderr_output <- sdk_process$read_error_lines()
    stop("SDK server failed to become healthy: ", paste(stderr_output, collapse = "\n"))
  }

  message("SDK server ready")

  shiny::runGadget(
    claude_sdk_ui(auth_config),
    claude_sdk_server_factory(base_url, working_dir, auth_config, sdk_process),
    viewer = shiny::browserViewer()
  )

  message("Shutting down SDK server...")
  sdk_process$kill()
  invisible(NULL)
}
