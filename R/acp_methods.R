acp_initialize <- function(client, client_info) {
  client$send_request("initialize", list(
    protocolVersion = "0.2.0",
    clientInfo = client_info,
    capabilities = list(
      filesystemAccess = TRUE,
      terminalAccess = TRUE
    )
  ))
}

acp_create_session <- function(client) {
  client$send_request("session/new", list())
}

acp_send_prompt <- function(client, session_id, prompt) {
  client$send_request("session/prompt", list(
    sessionId = session_id,
    prompt = list(
      role = "user",
      content = prompt
    )
  ))
}

acp_approve_permission <- function(client, request_id, decision) {
  if (!decision %in% c("allow", "allow_always", "reject")) {
    stop("Invalid decision: ", decision, ". Must be 'allow', 'allow_always', or 'reject'")
  }

  client$send_notification("session/approve_permission", list(
    requestId = request_id,
    decision = decision
  ))
}

acp_cancel_session <- function(client, session_id) {
  client$send_notification("session/cancel", list(
    sessionId = session_id
  ))
}
