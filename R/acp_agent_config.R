AGENT_CONFIGS <- list(
  claude = list(
    name = "Claude Code",
    command = "npx --yes @zed-industries/claude-code-acp",
    port = 8766,
    icon = "🤖"
  ),
  gemini = list(
    name = "Gemini CLI",
    command = "npx --yes @google/gemini-cli --experimental-acp",
    port = 8767,
    icon = "✨"
  )
)

get_agent_config <- function(agent_id) {
  if (!agent_id %in% names(AGENT_CONFIGS)) {
    return(NULL)
  }

  AGENT_CONFIGS[[agent_id]]
}

list_available_agents <- function() {
  available <- list()

  for (agent_id in names(AGENT_CONFIGS)) {
    config <- AGENT_CONFIGS[[agent_id]]

    if (check_agent_installed(config$command)) {
      available[[agent_id]] <- config
    }
  }

  available
}

check_agent_installed <- function(command) {
  parts <- strsplit(command, " ")[[1]]
  base_cmd <- parts[1]

  if (base_cmd == "npx") {
    npx_path <- Sys.which("npx")
    if (nchar(npx_path) == 0) {
      return(FALSE)
    }

    if (length(parts) >= 3) {
      package_name <- parts[3]

      result <- tryCatch({
        system2("npx", c("--yes", package_name, "--version"),
                stdout = TRUE, stderr = TRUE, timeout = 10)
      }, error = function(e) {
        NULL
      })

      return(!is.null(result))
    }
  }

  cmd_path <- Sys.which(base_cmd)
  nchar(cmd_path) > 0
}

get_agent_choices <- function() {
  agents <- list_available_agents()

  if (length(agents) == 0) {
    return(c("No agents available" = "none"))
  }

  choices <- sapply(agents, function(a) a$name)
  names(choices) <- names(agents)

  choices
}
