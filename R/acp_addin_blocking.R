claude_code_acp_addin_blocking <- function(agent = "claude") {
  if (!rstudioapi::isAvailable()) {
    stop("This addin requires RStudio")
  }

  agent_config <- get_agent_config(agent)
  if (is.null(agent_config)) {
    stop("Agent not found: ", agent)
  }

  proxy_port <- agent_config$port

  message("Starting ", agent_config$name, " via WebSocket proxy...")
  proxy_process <- start_websocket_proxy(agent = agent, port = proxy_port)

  message("Waiting for WebSocket proxy to be ready...")
  if (!check_websocket_ready(port = proxy_port, timeout = 10)) {
    stop_websocket_proxy(proxy_process)
    stop("WebSocket proxy failed to become ready")
  }

  message("WebSocket proxy ready")

  on.exit({
    message("Shutting down WebSocket proxy...")
    stop_websocket_proxy(proxy_process)
  })

  shiny::runGadget(
    claude_acp_ui(agent_config$name),
    claude_acp_server_factory(proxy_port, agent_config$name),
    viewer = shiny::browserViewer()
  )

  invisible(NULL)
}
