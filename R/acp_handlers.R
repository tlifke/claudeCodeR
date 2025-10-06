handle_session_update <- function(update, ui_callbacks) {
  if (is.null(update$params) || is.null(update$params$updateType)) {
    message("Received session update without updateType")
    return(invisible(NULL))
  }

  update_type <- update$params$updateType

  if (update_type == "content") {
    content <- update$params$content
    if (!is.null(ui_callbacks$on_text) && !is.null(content)) {
      ui_callbacks$on_text(content)
    }

  } else if (update_type == "thinking") {
    if (!is.null(ui_callbacks$on_thinking)) {
      ui_callbacks$on_thinking(update$params$thinking)
    }

  } else if (update_type == "toolUse") {
    if (!is.null(ui_callbacks$on_tool_use)) {
      tool_name <- update$params$toolName %||% "unknown"
      tool_input <- update$params$toolInput %||% list()
      ui_callbacks$on_tool_use(
        tool_name = tool_name,
        tool_input = tool_input
      )
    }

  } else if (update_type == "complete") {
    if (!is.null(ui_callbacks$on_complete)) {
      ui_callbacks$on_complete()
    }

  } else if (update_type == "error") {
    if (!is.null(ui_callbacks$on_error)) {
      error_msg <- update$params$error %||% "Unknown error"
      ui_callbacks$on_error(error_msg)
    }

  } else {
    message("Unknown update type: ", update_type)
  }

  invisible(NULL)
}

handle_permission_request <- function(request, client, auto_approve = TRUE) {
  if (is.null(request$params)) {
    message("Permission request missing params")
    return(invisible(NULL))
  }

  request_id <- request$params$requestId
  tool_call <- request$params$toolCall

  if (is.null(request_id) || is.null(tool_call)) {
    message("Permission request missing requestId or toolCall")
    return(invisible(NULL))
  }

  tool_name <- tool_call$name %||% "unknown"
  tool_input <- tool_call$input %||% list()

  message("Permission request: ", request_id, " for tool: ", tool_name)

  if (auto_approve) {
    decision <- "allow_always"
    message("Auto-approving permission: ", decision)
    acp_approve_permission(client, request_id, decision)
  } else {
    decision <- "reject"
    message("Rejecting permission (auto_approve = FALSE)")
    acp_approve_permission(client, request_id, decision)
  }

  invisible(NULL)
}

create_message_router <- function(client, ui_callbacks, auto_approve = TRUE) {
  function(message) {
    if (is.null(message$method)) {
      return(invisible(NULL))
    }

    method <- message$method

    if (method == "session/update") {
      handle_session_update(message, ui_callbacks)

    } else if (method == "session/request_permission") {
      handle_permission_request(message, client, auto_approve)

    } else {
      message("Unhandled method: ", method)
    }

    invisible(NULL)
  }
}
