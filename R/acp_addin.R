claude_code_acp_addin <- function(agent = "claude") {
  if (!rstudioapi::isAvailable()) {
    stop("This addin requires RStudio")
  }

  agent_config <- get_agent_config(agent)
  if (is.null(agent_config)) {
    available_agents <- list_available_agents()
    if (length(available_agents) == 0) {
      rstudioapi::showDialog(
        "No ACP Agents Found",
        paste0(
          "No ACP-compatible agents found.\n\n",
          "To use Claude Code via ACP, make sure Node.js is installed, then run:\n\n",
          "  npm install -g @zed-industries/claude-code-acp\n\n",
          "Or use npx (no install needed):\n\n",
          "  npx @zed-industries/claude-code-acp\n\n",
          "See documentation for other supported agents."
        )
      )
    } else {
      agent_names <- paste(sapply(available_agents, function(a) a$name), collapse = ", ")
      rstudioapi::showDialog(
        "Agent Not Found",
        paste0(
          "Agent '", agent, "' not found.\n\n",
          "Available agents: ", agent_names, "\n\n",
          "Example: claude_code_acp_addin(agent = 'claude')"
        )
      )
    }
    return(invisible(NULL))
  }

  proxy_port <- agent_config$port
  shiny_port <- find_available_port(8800)

  kill_process_on_port(proxy_port)
  kill_process_on_port(shiny_port)

  message("Starting ", agent_config$name, " via WebSocket proxy...")

  proxy_process <- tryCatch({
    start_websocket_proxy(agent = agent, port = proxy_port)
  }, error = function(e) {
    rstudioapi::showDialog(
      "Proxy Startup Failed",
      paste0(
        "Failed to start WebSocket proxy:\n\n",
        e$message, "\n\n",
        "Make sure websocketd and the agent are installed."
      )
    )
    stop(e)
  })

  message("Waiting for WebSocket proxy to be ready...")
  if (!check_websocket_ready(port = proxy_port, timeout = 10)) {
    stop_websocket_proxy(proxy_process)
    stop("WebSocket proxy failed to become ready")
  }

  message("WebSocket proxy ready")
  message("Starting Shiny app in background...")

  shiny_bg <- callr::r_bg(
    func = function(proxy_port, shiny_port, agent_name, pkg_path) {
      if (!is.null(pkg_path) && dir.exists(pkg_path)) {
        pkgload::load_all(pkg_path, export_all = FALSE, helpers = FALSE, quiet = TRUE)
      }

      app <- shiny::shinyApp(
        ui = claudeCodeR:::claude_acp_ui(agent_name),
        server = claudeCodeR:::claude_acp_server_factory(proxy_port, agent_name)
      )

      shiny::runApp(app, port = shiny_port, host = "127.0.0.1", launch.browser = FALSE)
    },
    args = list(
      proxy_port = proxy_port,
      shiny_port = shiny_port,
      agent_name = agent_config$name,
      pkg_path = tryCatch(find.package("claudeCodeR"), error = function(e) NULL)
    ),
    supervise = TRUE,
    stdout = "|",
    stderr = "|"
  )

  options(claude_code_acp_proxy_process = proxy_process)
  options(claude_code_acp_shiny_process = shiny_bg)
  options(claude_code_acp_agent = agent)

  Sys.sleep(2)

  if (!shiny_bg$is_alive()) {
    stderr_out <- shiny_bg$read_error()
    stdout_out <- shiny_bg$read_output()
    stop_websocket_proxy(proxy_process)
    error_msg <- paste0(
      "Shiny app failed to start\n\n",
      "STDERR:\n", stderr_out, "\n\n",
      "STDOUT:\n", stdout_out
    )
    stop(error_msg)
  }

  message("Waiting for Shiny to be ready on port ", shiny_port, "...")
  shiny_url <- paste0("http://127.0.0.1:", shiny_port)

  shiny_ready <- FALSE
  for (i in 1:20) {
    ready <- tryCatch({
      response <- httr::GET(shiny_url, httr::timeout(1))
      httr::status_code(response) == 200
    }, error = function(e) FALSE)

    if (ready) {
      shiny_ready <- TRUE
      break
    }
    Sys.sleep(0.5)
  }

  if (!shiny_ready) {
    stderr_out <- shiny_bg$read_error()
    stdout_out <- shiny_bg$read_output()
    stop_websocket_proxy(proxy_process)
    shiny_bg$kill()
    error_msg <- paste0(
      "Shiny app failed to become ready\n\n",
      "STDERR:\n", stderr_out, "\n\n",
      "STDOUT:\n", stdout_out
    )
    stop(error_msg)
  }

  message("Shiny ready, opening viewer...")
  rstudioapi::viewer(shiny_url)

  message(agent_config$name, " opened in viewer. Console is free.")
  message("To stop: Run claude_code_acp_stop()")
  invisible(NULL)
}

claude_code_acp_stop <- function() {
  shiny_proc <- getOption("claude_code_acp_shiny_process", NULL)
  proxy_proc <- getOption("claude_code_acp_proxy_process", NULL)

  if (!is.null(shiny_proc) && shiny_proc$is_alive()) {
    shiny_proc$kill()
    message("Stopped Shiny app")
  }

  if (!is.null(proxy_proc)) {
    stop_websocket_proxy(proxy_proc)
  }

  options(claude_code_acp_shiny_process = NULL)
  options(claude_code_acp_proxy_process = NULL)
  options(claude_code_acp_agent = NULL)

  message("Claude Code ACP stopped")
  invisible(NULL)
}
