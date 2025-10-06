claude_acp_ui <- function(agent_name = "Claude Code") {
  shiny::fluidPage(
    shiny::tags$head(
      shiny::tags$style(shiny::HTML("
        body {
          margin: 0;
          padding: 0;
          height: 100vh;
          overflow: hidden;
        }
        .container-fluid {
          height: 100vh;
          display: flex;
          flex-direction: column;
          padding: 0;
        }
        .header {
          background-color: #2c3e50;
          color: white;
          padding: 10px 15px;
          font-weight: bold;
          flex-shrink: 0;
        }
        .chat-container {
          flex: 1;
          overflow-y: auto;
          padding: 15px;
          background-color: #f9f9f9;
        }
        .message {
          margin: 10px 0;
          padding: 12px;
          border-radius: 8px;
          max-width: 85%;
        }
        .message.user {
          background-color: #e3f2fd;
          margin-left: auto;
          margin-right: 0;
        }
        .message.agent {
          background-color: #fff3e0;
          margin-right: auto;
          margin-left: 0;
        }
        .message.system {
          background-color: #f5f5f5;
          font-style: italic;
          text-align: center;
          font-size: 0.9em;
          max-width: 100%;
        }
        .streaming {
          border-left: 3px solid #ff9800;
        }
        .input-container {
          padding: 15px;
          background-color: white;
          border-top: 1px solid #ddd;
          flex-shrink: 0;
        }
        .status-bar {
          padding: 5px 15px;
          background-color: #ecf0f1;
          font-size: 0.85em;
          color: #666;
          flex-shrink: 0;
        }
        pre {
          background-color: #f4f4f4;
          padding: 10px;
          border-radius: 4px;
          overflow-x: auto;
        }
        code {
          background-color: #f4f4f4;
          padding: 2px 6px;
          border-radius: 3px;
          font-family: 'Courier New', monospace;
        }
      "))
    ),
    shiny::div(
      class = "header",
      shiny::textOutput("agent_header", inline = TRUE)
    ),
    shiny::div(
      class = "status-bar",
      shiny::textOutput("connection_status", inline = TRUE)
    ),
    shiny::div(
      class = "chat-container",
      shiny::uiOutput("chat_history")
    ),
    shiny::div(
      class = "input-container",
      shiny::textAreaInput(
        "user_prompt",
        NULL,
        placeholder = "Ask the agent to help with your code...",
        width = "100%",
        height = "100px"
      ),
      shiny::actionButton(
        "send_prompt",
        "Send",
        class = "btn-primary",
        width = "100%"
      )
    )
  )
}

claude_acp_server_factory <- function(proxy_port, agent_name = "Claude Code") {
  function(input, output, session) {
    values <- shiny::reactiveValues(
      messages = list(),
      streaming_message = "",
      trigger = 0,
      ws_client = NULL,
      acp_session_id = NULL,
      connected = FALSE,
      query_in_progress = FALSE
    )

    ws_url <- sprintf("ws://localhost:%d", proxy_port)

    shiny::observe({
      tryCatch({
        message("Initializing ACP WebSocket client to: ", ws_url)

        ws_client <- ACPWebSocketClient$new(
          ws_url = ws_url,
          on_message = create_message_router(
          client = NULL,
          ui_callbacks = list(
            on_text = function(text) {
              shiny::isolate({
                values$streaming_message <- paste0(values$streaming_message, text)
                values$trigger <- values$trigger + 1
              })
            },
            on_tool_use = function(tool_name, tool_input) {
              message("Tool use: ", tool_name)
            },
            on_complete = function() {
              message("Query complete")
              shiny::isolate({
                if (nchar(values$streaming_message) > 0) {
                  values$messages <- c(values$messages, list(list(
                    type = "agent",
                    content = values$streaming_message
                  )))
                  values$streaming_message <- ""
                }
                values$query_in_progress <- FALSE
                values$trigger <- values$trigger + 1
              })
            },
            on_error = function(error) {
              message("Query error: ", error)
              shiny::isolate({
                values$messages <- c(values$messages, list(list(
                  type = "system",
                  content = paste("Error:", error)
                )))
                values$streaming_message <- ""
                values$query_in_progress <- FALSE
                values$trigger <- values$trigger + 1
              })
            }
          ),
          auto_approve = TRUE
        ),
        on_error = function(error) {
          message("WebSocket error: ", error)
          shiny::showNotification(paste("WebSocket error:", error), type = "error")
        }
      )

      ws_client$connect()
      values$ws_client <- ws_client

      Sys.sleep(1)

      if (ws_client$is_connected()) {
        values$connected <- TRUE
        message("WebSocket connected, initializing ACP...")

        promises::then(
          acp_initialize(ws_client, list(
            name = "RStudio Claude Code",
            version = "0.3.0-acp"
          )),
          onFulfilled = function(result) {
            message("ACP initialized, creating session...")
            promises::then(
              acp_create_session(ws_client),
              onFulfilled = function(session_result) {
                message("Session created: ", session_result$sessionId)
                shiny::isolate({
                  values$acp_session_id <- session_result$sessionId
                  values$messages <- c(values$messages, list(list(
                    type = "system",
                    content = "Connected and ready!"
                  )))
                  values$trigger <- values$trigger + 1
                })
              },
              onRejected = function(error) {
                message("Failed to create session: ", error)
                shiny::showNotification("Failed to create session", type = "error")
              }
            )
          },
          onRejected = function(error) {
            message("Failed to initialize ACP: ", error)
            shiny::showNotification("Failed to initialize ACP", type = "error")
          }
        )
      } else {
        message("WebSocket connection failed")
        shiny::showNotification("Failed to connect to agent", type = "error")
      }
      }, error = function(e) {
        message("Error in observe block: ", e$message)
        shiny::isolate({
          values$messages <- c(values$messages, list(list(
            type = "system",
            content = paste("Connection error:", e$message)
          )))
          values$trigger <- values$trigger + 1
        })
      })
    })

    output$agent_header <- shiny::renderText({
      paste0(agent_name, " (ACP)")
    })

    output$connection_status <- shiny::renderText({
      if (values$connected && !is.null(values$acp_session_id)) {
        paste0("Connected · Session: ", substr(values$acp_session_id, 1, 8), "...")
      } else if (values$connected) {
        "Connecting..."
      } else {
        "Disconnected"
      }
    })

    shiny::observeEvent(input$send_prompt, {
      prompt_text <- input$user_prompt

      if (nchar(trimws(prompt_text)) == 0) {
        return()
      }

      if (values$query_in_progress) {
        shiny::showNotification("Please wait for current query to complete", type = "warning")
        return()
      }

      if (is.null(values$acp_session_id)) {
        shiny::showNotification("Session not ready", type = "warning")
        return()
      }

      shiny::isolate({
        values$messages <- c(values$messages, list(list(
          type = "user",
          content = prompt_text
        )))
        values$trigger <- values$trigger + 1
        values$query_in_progress <- TRUE
        values$streaming_message <- ""
      })

      shiny::updateTextAreaInput(session, "user_prompt", value = "")

      editor_context <- tryCatch({
        get_editor_context()
      }, error = function(e) {
        NULL
      })

      full_prompt <- prompt_text
      if (!is.null(editor_context)) {
        context_parts <- c()
        if (!is.null(editor_context$path)) {
          context_parts <- c(context_parts, paste0("Current file: ", editor_context$path))
        }
        if (!is.null(editor_context$selection) && !is.null(editor_context$selection$text)) {
          context_parts <- c(context_parts, paste0("Selected code:\n```\n", editor_context$selection$text, "\n```"))
        } else if (!is.null(editor_context$content)) {
          context_parts <- c(context_parts, paste0("File content:\n```\n", editor_context$content, "\n```"))
        }
        if (length(context_parts) > 0) {
          full_prompt <- paste0(paste(context_parts, collapse = "\n\n"), "\n\n", prompt_text)
        }
      }

      message("Sending prompt to ACP agent...")
      acp_send_prompt(values$ws_client, values$acp_session_id, full_prompt)
    })

    output$chat_history <- shiny::renderUI({
      values$trigger

      messages <- lapply(values$messages, function(msg) {
        shiny::div(
          class = paste("message", msg$type),
          shiny::HTML(markdown_to_html(msg$content))
        )
      })

      if (nchar(values$streaming_message) > 0) {
        messages <- c(messages, list(
          shiny::div(
            class = "message agent streaming",
            shiny::HTML(markdown_to_html(values$streaming_message))
          )
        ))
      }

      shiny::tagList(messages)
    })

    session$onSessionEnded(function() {
      if (!is.null(values$ws_client)) {
        if (!is.null(values$acp_session_id)) {
          tryCatch({
            acp_cancel_session(values$ws_client, values$acp_session_id)
          }, error = function(e) {
            message("Error canceling session: ", e$message)
          })
        }
        values$ws_client$close()
      }
    })
  }
}
