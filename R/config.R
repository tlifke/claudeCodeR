detect_auth_method <- function() {
  api_key <- Sys.getenv("ANTHROPIC_API_KEY", "")
  if (nchar(api_key) > 0) {
    return(list(
      method = "api_key",
      api_key = api_key,
      permission_mode = "acceptEdits"
    ))
  }

  use_bedrock <- Sys.getenv("CLAUDE_CODE_USE_BEDROCK", "")
  if (use_bedrock == "1") {
    aws_region <- Sys.getenv("AWS_REGION", "us-east-1")
    aws_profile <- Sys.getenv("AWS_PROFILE", "")

    has_direct_creds <- nchar(Sys.getenv("AWS_ACCESS_KEY_ID", "")) > 0 &&
                        nchar(Sys.getenv("AWS_SECRET_ACCESS_KEY", "")) > 0

    return(list(
      method = "bedrock",
      aws_region = aws_region,
      aws_profile = if (nchar(aws_profile) > 0) aws_profile else NULL,
      has_direct_creds = has_direct_creds,
      permission_mode = "acceptEdits"
    ))
  }

  if (check_claude_cli_auth()) {
    return(list(
      method = "subscription",
      permission_mode = "acceptEdits"
    ))
  }

  NULL
}

check_claude_cli_auth <- function() {
  claude_paths <- c(
    "/Users/tylerlifke/.npm-global/bin/claude",
    "~/.npm-global/bin/claude",
    "/usr/local/bin/claude",
    "~/.local/bin/claude",
    Sys.which("claude")
  )

  claude_path <- NULL
  for (path in claude_paths) {
    expanded_path <- path.expand(path)
    if (file.exists(expanded_path)) {
      claude_path <- expanded_path
      break
    }
  }

  if (is.null(claude_path) || claude_path == "") {
    return(FALSE)
  }

  result <- system2(claude_path, "--version", stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(result, "status")) && attr(result, "status") != 0) {
    return(FALSE)
  }

  version_output <- paste(result, collapse = " ")
  if (!grepl("Claude Code", version_output, ignore.case = TRUE)) {
    return(FALSE)
  }

  claude_dir <- path.expand("~/.claude")
  if (dir.exists(claude_dir)) {
    settings_file <- file.path(claude_dir, "settings.json")
    if (file.exists(settings_file)) {
      return(TRUE)
    }
  }

  TRUE
}

validate_aws_credentials <- function(auth_config) {
  if (auth_config$method != "bedrock") {
    return(TRUE)
  }

  if (auth_config$has_direct_creds) {
    return(TRUE)
  }

  profile <- auth_config$aws_profile
  if (is.null(profile)) {
    profile <- ""
  }

  result <- system2(
    "aws",
    c("sts", "get-caller-identity"),
    env = if (nchar(profile) > 0) c(AWS_PROFILE = profile) else character(),
    stdout = FALSE,
    stderr = FALSE
  )

  result == 0
}

prompt_aws_sso_login <- function(profile = NULL) {
  if (!rstudioapi::isAvailable()) {
    stop("AWS SSO login requires RStudio")
  }

  if (is.null(profile)) {
    profile <- rstudioapi::showPrompt(
      "AWS SSO Login",
      "Enter AWS profile name:",
      default = Sys.getenv("AWS_PROFILE", "default")
    )

    if (is.null(profile)) {
      stop("AWS profile required")
    }
  }

  message("Logging in to AWS SSO with profile: ", profile)

  result <- system2(
    "aws",
    c("sso", "login", "--profile", profile),
    wait = TRUE
  )

  if (result != 0) {
    stop("AWS SSO login failed")
  }

  Sys.setenv(AWS_PROFILE = profile)

  TRUE
}

get_working_dir <- function() {
  if (rstudioapi::isAvailable()) {
    project_dir <- tryCatch({
      rstudioapi::getActiveProject()
    }, error = function(e) NULL)

    if (!is.null(project_dir)) {
      return(normalizePath(project_dir))
    }
  }

  normalizePath(getwd())
}

find_python310 <- function() {
  python_candidates <- c("python3.12", "python3.11", "python3.10", "python3")

  for (py_cmd in python_candidates) {
    py_path <- Sys.which(py_cmd)
    if (py_path != "" && nchar(py_path) > 0) {
      version_output <- system2(py_path, "--version", stdout = TRUE, stderr = TRUE)
      version_str <- paste(version_output, collapse = " ")

      if (grepl("Python 3\\.(1[0-9]|[2-9][0-9])", version_str)) {
        return(py_path)
      }
    }
  }

  stop("Python 3.10+ is required but not found. Please install Python 3.10 or newer.\n",
       "Visit: https://www.python.org/downloads/")
}

setup_python_venv <- function() {
  venv_path <- path.expand("~/.claude-rstudio-venv")

  if (!dir.exists(venv_path)) {
    python_cmd <- find_python310()
    message("Creating Python virtual environment (one-time setup)...")
    message("Using: ", python_cmd)
    result <- system2(python_cmd, c("-m", "venv", venv_path))
    if (result != 0) {
      stop("Failed to create virtual environment.")
    }
  }

  python_bin <- file.path(venv_path, "bin", "python")
  pip_bin <- file.path(venv_path, "bin", "pip")

  if (!file.exists(python_bin)) {
    stop("Virtual environment Python not found at: ", python_bin)
  }

  message("Upgrading pip...")
  system2(python_bin, c("-m", "pip", "install", "--upgrade", "pip"),
          stdout = FALSE, stderr = FALSE)

  requirements_file <- system.file("python/requirements.txt", package = "claudeCodeR")
  if (!file.exists(requirements_file)) {
    requirements_file <- file.path(
      find.package("claudeCodeR"),
      "..",
      "..",
      "r-studio-claude-code-addin",
      "python",
      "requirements.txt"
    )
  }

  marker_file <- file.path(venv_path, ".deps_installed")
  if (!file.exists(marker_file) || file.exists(requirements_file)) {
    message("Installing Python dependencies (this may take a minute)...")
    result <- system2(pip_bin, c("install", "-r", requirements_file),
                      stdout = TRUE, stderr = TRUE)

    if (!is.null(attr(result, "status")) && attr(result, "status") != 0) {
      error_output <- paste(result, collapse = "\n")
      stop("Failed to install Python dependencies:\n", error_output)
    }
    file.create(marker_file)
    message("Dependencies installed successfully!")
  }

  python_bin
}

start_sdk_server <- function(working_dir, auth_config, port = 8765) {
  python_bin <- setup_python_venv()

  python_script <- system.file("python/sdk_server.py", package = "claudeCodeR")

  if (!file.exists(python_script)) {
    python_script <- file.path(
      find.package("claudeCodeR"),
      "..",
      "..",
      "r-studio-claude-code-addin",
      "python",
      "sdk_server.py"
    )
  }

  if (!file.exists(python_script)) {
    stop("SDK server script not found at: ", python_script)
  }

  env_vars <- c(
    PORT = as.character(port),
    HOST = "127.0.0.1"
  )

  current_path <- Sys.getenv("PATH")

  claude_path <- Sys.which("claude")
  if (nchar(claude_path) > 0) {
    claude_bin_dir <- dirname(claude_path)
    if (!grepl(claude_bin_dir, current_path, fixed = TRUE)) {
      env_vars["PATH"] <- paste0(claude_bin_dir, ":", current_path)
    } else {
      env_vars["PATH"] <- current_path
    }
  } else {
    env_vars["PATH"] <- current_path
  }

  if (auth_config$method == "api_key") {
    env_vars["ANTHROPIC_API_KEY"] <- auth_config$api_key
  } else if (auth_config$method == "bedrock") {
    env_vars["CLAUDE_CODE_USE_BEDROCK"] <- "1"
    env_vars["AWS_REGION"] <- auth_config$aws_region
    if (!is.null(auth_config$aws_profile)) {
      env_vars["AWS_PROFILE"] <- auth_config$aws_profile
    }
    if (auth_config$has_direct_creds) {
      env_vars["AWS_ACCESS_KEY_ID"] <- Sys.getenv("AWS_ACCESS_KEY_ID")
      env_vars["AWS_SECRET_ACCESS_KEY"] <- Sys.getenv("AWS_SECRET_ACCESS_KEY")
      session_token <- Sys.getenv("AWS_SESSION_TOKEN", "")
      if (nchar(session_token) > 0) {
        env_vars["AWS_SESSION_TOKEN"] <- session_token
      }
    }
  }

  proc <- processx::process$new(
    python_bin,
    c(python_script),
    env = env_vars,
    stdout = "|",
    stderr = "|",
    cleanup = TRUE
  )

  Sys.sleep(2)

  if (!proc$is_alive()) {
    tryCatch({
      stderr_output <- proc$read_all_error_lines()
      stdout_output <- proc$read_all_output_lines()
      error_msg <- c(
        "SDK server failed to start.",
        "STDERR:",
        stderr_output,
        "STDOUT:",
        stdout_output
      )
      stop(paste(error_msg, collapse = "\n"))
    }, error = function(e) {
      stop("SDK server failed to start and error output could not be read. ",
           "The process may have crashed immediately. ",
           "Check that Python 3.10+ is installed: ", python_bin)
    })
  }

  proc
}

wait_for_server <- function(base_url, timeout = 10, interval = 0.5) {
  start_time <- Sys.time()

  while (as.numeric(difftime(Sys.time(), start_time, units = "secs")) < timeout) {
    tryCatch({
      response <- httr::GET(paste0(base_url, "/health"), httr::timeout(1))
      if (!httr::http_error(response)) {
        return(TRUE)
      }
    }, error = function(e) {
    })

    Sys.sleep(interval)
  }

  FALSE
}
