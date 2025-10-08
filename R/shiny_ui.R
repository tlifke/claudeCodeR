claude_sdk_ui <- function(auth_config) {
  auth_method_label <- if (auth_config$method == "api_key") {
    "Anthropic API"
  } else if (auth_config$method == "bedrock") {
    paste0("AWS Bedrock (", auth_config$aws_region, ")")
  } else if (auth_config$method == "subscription") {
    "Claude Subscription"
  } else {
    "Unknown"
  }

  miniUI::miniPage(
    miniUI::gadgetTitleBar("Claude Code"),
    miniUI::miniContentPanel(
      shiny::tags$head(
        shiny::tags$style(shiny::HTML("
          .chat-container {
            height: calc(100vh - 220px);
            overflow-y: auto;
            padding: 10px;
            border: 1px solid #ddd;
            background-color: #f9f9f9;
            margin-bottom: 10px;
          }
          .message {
            margin: 10px 0;
            padding: 10px;
            border-radius: 5px;
          }
          .message.user {
            background-color: #e3f2fd;
            margin-left: 20%;
          }
          .message.agent {
            background-color: #fff3e0;
            margin-right: 20%;
          }
          .message.system {
            background-color: #f5f5f5;
            font-style: italic;
            text-align: center;
            font-size: 0.9em;
          }
          .auth-info {
            font-size: 0.85em;
            color: #666;
            padding: 5px 10px;
            background-color: #f0f0f0;
            border-radius: 3px;
            margin-bottom: 10px;
          }
          .streaming {
            border-left: 3px solid #ff9800;
          }
        "))
      ),
      shiny::div(
        class = "auth-info",
        shiny::textOutput("auth_status", inline = TRUE)
      ),
      shiny::div(
        class = "chat-container",
        shiny::uiOutput("chat_history")
      ),
      shiny::textAreaInput(
        "user_prompt",
        NULL,
        placeholder = "Ask Claude to help with your code...",
        width = "100%",
        height = "80px"
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

claude_sdk_server_factory <- function(base_url, working_dir, auth_config, sdk_process) {
  function(input, output, session) {
    values <- shiny::reactiveValues(
      messages = list(),
      streaming_message = "",
      trigger = 0,
      client = NULL,
      session_initialized = FALSE,
      pending_permission = NULL,
      sdk_process = sdk_process,
      bg_process = NULL,
      show_permission_modal = FALSE
    )

    message_file_path <- shiny::reactiveVal(NULL)

    shiny::observeEvent(session$clientData, once = TRUE, {
      message("Initializing SDK client...")
      values$client <- ClaudeSDKClient(base_url)

      message("Calling initialize_session...")
      tryCatch({
        values$client <- initialize_session(values$client, working_dir, auth_config)
        values$session_initialized <- TRUE
        message("Session initialized successfully!")
        add_system_message(values, "Ready to assist!")
      }, error = function(e) {
        message("Initialization failed: ", e$message)
        add_system_message(values, paste("Initialization error:", e$message))
      })
    })

    output$auth_status <- shiny::renderText({
      if (auth_config$method == "api_key") {
        "Connected: Anthropic API"
      } else if (auth_config$method == "bedrock") {
        profile_text <- if (!is.null(auth_config$aws_profile)) {
          paste0(" (", auth_config$aws_profile, ")")
        } else {
          ""
        }
        paste0("Connected: AWS Bedrock ", auth_config$aws_region, profile_text)
      } else if (auth_config$method == "subscription") {
        "Connected: Claude Subscription"
      }
    })

    shiny::observeEvent(values$show_permission_modal, {
      if (values$show_permission_modal && !is.null(values$pending_permission)) {
        msg <- values$pending_permission
        shiny::showModal(shiny::modalDialog(
          title = "Permission Request",
          shiny::p(sprintf("Claude wants to use the %s tool:", msg$tool_name)),
          shiny::pre(jsonlite::toJSON(msg$input, pretty = TRUE, auto_unbox = TRUE)),
          footer = shiny::tagList(
            shiny::actionButton("approve_permission", "Approve", class = "btn-success"),
            shiny::actionButton("deny_permission", "Deny", class = "btn-danger")
          ),
          easyClose = FALSE
        ))
        values$show_permission_modal <- FALSE
      }
    })

    shiny::observeEvent(input$send_prompt, {
      message("Send button clicked!")

      if (!values$session_initialized) {
        message("Session not initialized!")
        shiny::showNotification("Session not ready. Please wait...", type = "warning")
        return()
      }

      if (!is.null(values$bg_process) && values$bg_process$is_alive()) {
        message("Query already in progress!")
        shiny::showNotification("Please wait for current query to complete", type = "warning")
        return()
      }

      prompt_text <- input$user_prompt
      message("Prompt text: ", prompt_text)

      if (nchar(trimws(prompt_text)) == 0) {
        message("Empty prompt")
        return()
      }

      add_user_message(values, prompt_text)
      shiny::updateTextAreaInput(session, "user_prompt", value = "")

      message("Getting editor context...")
      editor_context <- tryCatch({
        get_editor_context()
      }, error = function(e) {
        message("Editor context error: ", e$message)
        NULL
      })

      values$streaming_message <- ""

      message("Sending query to SDK in background...")

      message_file <- tempfile(fileext = ".jsonl")
      file.create(message_file)
      message_file_path(message_file)

      client_copy <- values$client
      bg_process_ref <- NULL
      last_read_line <- 0

      bg_process_ref <- callr::r_bg(
        func = function(client, prompt, context, message_file) {
          cat("Background process started\n", file = stderr())
          library(curl)
          library(jsonlite)
          library(httr)
          cat("Libraries loaded\n", file = stderr())

          parse_sse_line <- function(line) {
            line <- gsub("\r$", "", line)
            if (startsWith(line, "event: ")) {
              return(list(type = "event", value = substring(line, 8)))
            } else if (startsWith(line, "data: ")) {
              return(list(type = "data", value = substring(line, 7)))
            } else if (line == "") {
              return(list(type = "separator"))
            }
            NULL
          }

          query_streaming <- function(client, prompt, context = NULL,
                                     on_text = NULL, on_permission = NULL,
                                     on_complete = NULL, on_error = NULL) {
            url <- paste0(client$base_url, "/query")
            cat("URL:", url, "\n", file = stderr())
            cat("Prompt:", prompt, "\n", file = stderr())

            body <- list(prompt = prompt)
            if (!is.null(context)) body$context <- context

            accumulated_text <- character()
            current_event <- NULL
            current_data <- NULL
            callback_count <- 0

            stream_callback <- function(data) {
              callback_count <<- callback_count + 1
              cat("Stream callback called (#", callback_count, "), bytes:", length(data), "\n", file = stderr())

              raw_text <- rawToChar(data)
              cat("Raw data:", substr(raw_text, 1, 200), "\n", file = stderr())

              lines <- strsplit(raw_text, "\n")[[1]]

              for (i in seq_along(lines)) {
                line <- lines[i]
                cat("Line", i, "length:", nchar(line), "repr:", deparse(line), "\n", file = stderr())
                parsed <- parse_sse_line(line)

                if (!is.null(parsed)) {
                  cat("Parsed:", parsed$type, "\n", file = stderr())

                  if (parsed$type == "event") {
                    current_event <<- parsed$value
                  } else if (parsed$type == "data") {
                    current_data <<- parsed$value
                  } else if (parsed$type == "separator" && !is.null(current_event)) {
                    cat("Processing event:", current_event, "\n", file = stderr())
                    event_data <- jsonlite::fromJSON(current_data)

                    if (current_event == "text") {
                      accumulated_text <<- c(accumulated_text, event_data$text)
                      if (!is.null(on_text)) on_text(event_data$text)
                    } else if (current_event == "tool_result") {
                      result_text <- paste0("\n```\n", event_data$content, "\n```\n")
                      accumulated_text <<- c(accumulated_text, result_text)
                      if (!is.null(on_text)) on_text(result_text)
                    } else if (current_event == "permission_request") {
                      if (!is.null(on_permission)) {
                        on_permission(event_data$request_id, event_data$tool_name, event_data$input)
                      }
                    } else if (current_event == "complete") {
                      if (!is.null(on_complete)) on_complete()
                    } else if (current_event == "error") {
                      error_message <- event_data$message %||% event_data$error
                      error_type <- event_data$error_type %||% "unknown"
                      if (!is.null(on_error)) on_error(error_message, error_type)
                    }

                    current_event <<- NULL
                    current_data <<- NULL
                  }
                } else {
                  cat("Parsed: NULL\n", file = stderr())
                }
              }
            }

            handle <- curl::new_handle()
            curl::handle_setopt(handle, timeout = 300L)
            curl::handle_setheaders(handle,
              "Content-Type" = "application/json",
              "Accept" = "text/event-stream"
            )

            body_json <- jsonlite::toJSON(body, auto_unbox = TRUE)
            cat("Request body:", body_json, "\n", file = stderr())
            curl::handle_setopt(handle, post = TRUE, postfields = body_json)

            cat("Making curl request...\n", file = stderr())
            result <- curl::curl_fetch_stream(url, fun = stream_callback, handle = handle)
            cat("Curl completed. Status:", result$status_code, "\n", file = stderr())
            cat("Callback was called", callback_count, "times\n", file = stderr())

            paste(accumulated_text, collapse = "")
          }

          approve_permission <- function(client, request_id, approved) {
            url <- paste0(client$base_url, "/approve")

            response <- httr::POST(
              url,
              body = list(
                request_id = request_id,
                approved = approved
              ),
              encode = "json",
              httr::timeout(5)
            )

            invisible(NULL)
          }

          accumulated_text <- character()

          cat("About to call query_streaming\n", file = stderr())
          tryCatch({
            query_streaming(
              client,
              prompt,
              context = context,
              on_text = function(text) {
                msg <- list(type = "text", content = text)
                cat(jsonlite::toJSON(msg, auto_unbox = TRUE), "\n",
                    file = message_file, append = TRUE)
                accumulated_text <<- c(accumulated_text, text)
              },
              on_permission = function(request_id, tool_name, input_data) {
                msg <- list(
                  type = "permission_request",
                  request_id = request_id,
                  tool_name = tool_name,
                  input = input_data
                )
                cat(jsonlite::toJSON(msg, auto_unbox = TRUE), "\n",
                    file = message_file, append = TRUE)

                response_file <- paste0(message_file, ".response.", request_id)

                while (!file.exists(response_file)) {
                  Sys.sleep(0.1)
                }

                response <- readLines(response_file, warn = FALSE)
                unlink(response_file)

                invisible(NULL)
              },
              on_complete = function() {
                msg <- list(type = "complete")
                cat(jsonlite::toJSON(msg, auto_unbox = TRUE), "\n",
                    file = message_file, append = TRUE)
              },
              on_error = function(error_message, error_type) {
                msg <- list(type = "error", message = error_message, error_type = error_type)
                cat(jsonlite::toJSON(msg, auto_unbox = TRUE), "\n",
                    file = message_file, append = TRUE)
              }
            )
            cat("query_streaming completed\n", file = stderr())
          }, error = function(e) {
            cat("ERROR in query_streaming: ", e$message, "\n", file = stderr())
            msg <- list(type = "error", message = e$message)
            cat(jsonlite::toJSON(msg, auto_unbox = TRUE), "\n",
                file = message_file, append = TRUE)
          })

          paste(accumulated_text, collapse = "")
        },
        args = list(
          client = client_copy,
          prompt = prompt_text,
          context = editor_context,
          message_file = message_file
        ),
        supervise = TRUE,
        stderr = "|"
      )
      values$bg_process <- bg_process_ref

      poll_messages <- function() {
        shiny::isolate({
          if (!file.exists(message_file)) {
            return()
          }

          all_lines <- readLines(message_file, warn = FALSE)

          if (length(all_lines) > last_read_line) {
            new_lines <- all_lines[(last_read_line + 1):length(all_lines)]
            last_read_line <<- length(all_lines)

            for (line in new_lines) {
              msg <- jsonlite::fromJSON(line)

              if (msg$type == "text") {
                values$streaming_message <- paste0(values$streaming_message, msg$content)
                values$trigger <- values$trigger + 1

              } else if (msg$type == "permission_request") {
                message("Permission request: ", msg$request_id, " for ", msg$tool_name)
                values$pending_permission <- msg
                values$show_permission_modal <- TRUE

              } else if (msg$type == "complete") {
                message("Query complete")
                if (nchar(values$streaming_message) > 0) {
                  add_agent_message(values, values$streaming_message)
                }
                values$streaming_message <- ""
                values$bg_process <- NULL
                return()

              } else if (msg$type == "error") {
                message("Query error: ", msg$message)
                add_system_message(values, paste("Error:", msg$message))
                values$streaming_message <- ""
                values$bg_process <- NULL
                return()
              }
            }
          }

          if (bg_process_ref$is_alive()) {
            later::later(poll_messages, delay = 0.1)
          } else {
            message("Background process ended")
            values$bg_process <- NULL

            stderr_output <- bg_process_ref$read_error()
            if (nchar(stderr_output) > 0) {
              message("Background stderr: ", stderr_output)
            }

            tryCatch({
              result <- bg_process_ref$get_result()
              message("Background process result: ", result)
            }, error = function(e) {
              message("Background process error: ", e$message)
              error_msg <- paste("Background error:", e$message)
              if (nchar(stderr_output) > 0) {
                error_msg <- paste0(error_msg, "\nStderr: ", stderr_output)
              }
              add_system_message(values, error_msg)
              values$trigger <- values$trigger + 1
            })
            if (!is.null(message_file) && file.exists(message_file)) {
              unlink(message_file)
            }
          }
        })
      }

      later::later(poll_messages, delay = 0.1)
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

    shiny::observeEvent(input$approve_permission, {
      if (!is.null(values$pending_permission)) {
        message("Approving permission: ", values$pending_permission$request_id)
        tryCatch({
          approve_permission(values$client, values$pending_permission$request_id, TRUE)

          msg_file <- message_file_path()
          if (!is.null(msg_file)) {
            response_file <- paste0(msg_file, ".response.", values$pending_permission$request_id)
            writeLines("approved", response_file)
          }

          values$pending_permission <- NULL
          shiny::removeModal()
        }, error = function(e) {
          message("Approve error: ", e$message)
          shiny::showNotification(paste("Approve failed:", e$message), type = "error")
        })
      }
    })

    shiny::observeEvent(input$deny_permission, {
      if (!is.null(values$pending_permission)) {
        message("Denying permission: ", values$pending_permission$request_id)
        tryCatch({
          approve_permission(values$client, values$pending_permission$request_id, FALSE)

          msg_file <- message_file_path()
          if (!is.null(msg_file)) {
            response_file <- paste0(msg_file, ".response.", values$pending_permission$request_id)
            writeLines("denied", response_file)
          }

          values$pending_permission <- NULL
          shiny::removeModal()
        }, error = function(e) {
          message("Deny error: ", e$message)
          shiny::showNotification(paste("Deny failed:", e$message), type = "error")
        })
      }
    })

    shiny::observeEvent(input$done, {
      if (!is.null(values$client)) {
        shutdown_session(values$client)
      }
      shiny::stopApp()
    })

    session$onSessionEnded(function() {
      client <- shiny::isolate(values$client)
      if (!is.null(client)) {
        shutdown_session(client)
      }
    })
  }
}

add_user_message <- function(values, content) {
  values$messages <- c(values$messages, list(list(type = "user", content = content)))
}

add_agent_message <- function(values, content) {
  values$messages <- c(values$messages, list(list(type = "agent", content = content)))
}

add_system_message <- function(values, content) {
  values$messages <- c(values$messages, list(list(type = "system", content = content)))
}

markdown_to_html <- function(text) {
  text <- gsub("```([^`]+)```", "<pre><code>\\1</code></pre>", text)
  text <- gsub("`([^`]+)`", "<code>\\1</code>", text)
  text <- gsub("\n", "<br>", text)
  text
}
