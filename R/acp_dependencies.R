find_websocketd <- function() {
  sys_websocketd <- Sys.which("websocketd")
  if (nchar(sys_websocketd) > 0) {
    return(as.character(sys_websocketd))
  }

  user_websocketd <- path.expand("~/.claude-rstudio/bin/websocketd")
  if (.Platform$OS.type == "windows") {
    user_websocketd <- paste0(user_websocketd, ".exe")
  }

  if (file.exists(user_websocketd)) {
    return(user_websocketd)
  }

  message("websocketd not found. Installing to user directory...")
  install_websocketd()
  return(user_websocketd)
}

install_websocketd <- function() {
  bin_dir <- path.expand("~/.claude-rstudio/bin")
  if (!dir.exists(bin_dir)) {
    dir.create(bin_dir, recursive = TRUE)
  }

  os <- tolower(Sys.info()["sysname"])
  arch <- Sys.info()["machine"]

  version <- "0.4.1"
  base_url <- sprintf("https://github.com/joewalnes/websocketd/releases/download/v%s", version)

  if (os == "darwin") {
    platform <- "darwin_amd64"
    binary_name <- "websocketd"
  } else if (os == "linux") {
    if (grepl("arm|aarch64", arch, ignore.case = TRUE)) {
      platform <- "linux_arm64"
    } else {
      platform <- "linux_amd64"
    }
    binary_name <- "websocketd"
  } else if (os == "windows") {
    platform <- "windows_amd64"
    binary_name <- "websocketd.exe"
  } else {
    stop("Unsupported platform: ", os, ". Please install websocketd manually from:\n",
         "https://github.com/joewalnes/websocketd/releases")
  }

  zip_name <- sprintf("websocketd-%s-%s.zip", version, platform)
  download_url <- paste0(base_url, "/", zip_name)

  temp_zip <- tempfile(fileext = ".zip")
  temp_dir <- tempfile()
  dir.create(temp_dir)

  message("Downloading websocketd for ", platform, "...")
  message("URL: ", download_url)

  tryCatch({
    download.file(download_url, temp_zip, mode = "wb", quiet = FALSE)

    message("Extracting websocketd...")
    utils::unzip(temp_zip, exdir = temp_dir)

    extracted_binary <- file.path(temp_dir, binary_name)
    if (!file.exists(extracted_binary)) {
      stop("Binary not found after extraction. Expected: ", extracted_binary)
    }

    target_binary <- file.path(bin_dir, binary_name)
    file.copy(extracted_binary, target_binary, overwrite = TRUE)

    if (.Platform$OS.type != "windows") {
      Sys.chmod(target_binary, mode = "0755")
    }

    unlink(temp_zip)
    unlink(temp_dir, recursive = TRUE)

    message("websocketd installed successfully to: ", target_binary)

    target_binary
  }, error = function(e) {
    unlink(temp_zip)
    unlink(temp_dir, recursive = TRUE)

    error_msg <- sprintf(
      "Failed to install websocketd: %s\n\nPlease install manually:\n\n",
      e$message
    )

    if (os == "darwin") {
      error_msg <- paste0(error_msg, "  brew install websocketd\n\nOr download from:\n")
    } else if (os == "linux") {
      error_msg <- paste0(error_msg,
        "  wget https://github.com/joewalnes/websocketd/releases/download/v0.4.1/websocketd-0.4.1-linux_amd64.zip\n",
        "  unzip websocketd-0.4.1-linux_amd64.zip\n",
        "  mkdir -p ~/.local/bin\n",
        "  mv websocketd ~/.local/bin/\n",
        "  export PATH=$PATH:~/.local/bin\n\nOr download from:\n")
    } else if (os == "windows") {
      error_msg <- paste0(error_msg, "Download from:\n")
    }

    error_msg <- paste0(error_msg, "  https://github.com/joewalnes/websocketd/releases")

    stop(error_msg)
  })
}

check_websocketd_version <- function(websocketd_path) {
  result <- tryCatch({
    output <- system2(websocketd_path, "--version", stdout = TRUE, stderr = TRUE)
    paste(output, collapse = " ")
  }, error = function(e) {
    ""
  })

  if (grepl("websocketd", result, ignore.case = TRUE)) {
    return(TRUE)
  }

  FALSE
}

find_acp_agent <- function(agent_name = "claude") {
  if (agent_name == "claude") {
    command <- "npx"
    args <- c("@zed-industries/claude-code-acp", "--version")
  } else if (agent_name == "gemini") {
    command <- "npx"
    args <- c("@google/gemini-cli", "--version")
  } else {
    stop("Unknown agent: ", agent_name)
  }

  npx_path <- Sys.which("npx")
  if (nchar(npx_path) == 0) {
    stop("npx (Node.js) is required but not found. Please install Node.js from:\n",
         "https://nodejs.org/")
  }

  result <- tryCatch({
    system2(command, args, stdout = TRUE, stderr = TRUE)
  }, error = function(e) {
    NULL
  })

  if (!is.null(result)) {
    return(TRUE)
  }

  FALSE
}

get_installation_instructions <- function(agent_name = "claude") {
  if (agent_name == "claude") {
    return(paste0(
      "Claude Code ACP agent not found.\n\n",
      "Install with:\n",
      "  npm install -g @zed-industries/claude-code-acp\n\n",
      "Or use npx (no install needed):\n",
      "  npx @zed-industries/claude-code-acp\n\n",
      "Make sure Node.js is installed: https://nodejs.org/"
    ))
  } else if (agent_name == "gemini") {
    return(paste0(
      "Gemini CLI ACP agent not found.\n\n",
      "Install with:\n",
      "  npm install -g @google/gemini-cli\n\n",
      "Or use npx (no install needed):\n",
      "  npx @google/gemini-cli --experimental-acp\n\n",
      "Make sure Node.js is installed: https://nodejs.org/"
    ))
  }

  "Unknown agent"
}
