ClaudeSDKClient <- function(base_url = "http://127.0.0.1:8765") {
  structure(
    list(
      base_url = base_url,
      session_active = FALSE
    ),
    class = "ClaudeSDKClient"
  )
}

initialize_session <- function(client, working_dir, auth_config) {
  url <- paste0(client$base_url, "/initialize")

  body <- list(
    working_dir = working_dir,
    auth_method = auth_config$method,
    permission_mode = auth_config$permission_mode %||% "acceptEdits"
  )

  if (auth_config$method == "api_key") {
    body$api_key <- auth_config$api_key
  } else if (auth_config$method == "bedrock") {
    if (!is.null(auth_config$aws_region)) {
      body$aws_region <- auth_config$aws_region
    }
    if (!is.null(auth_config$aws_profile)) {
      body$aws_profile <- auth_config$aws_profile
    }
  }

  response <- httr::POST(
    url,
    body = body,
    encode = "json",
    httr::timeout(10)
  )

  if (httr::http_error(response)) {
    content <- httr::content(response, as = "text", encoding = "UTF-8")
    stop("Failed to initialize session: ", content)
  }

  result <- httr::content(response, as = "parsed")
  client$session_active <- TRUE
  client
}

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
                           on_text = NULL, on_permission = NULL, on_complete = NULL, on_error = NULL) {
  if (!client$session_active) {
    stop("Session not initialized. Call initialize_session() first.")
  }

  url <- paste0(client$base_url, "/query")

  body <- list(prompt = prompt)
  if (!is.null(context)) {
    body$context <- context
  }

  accumulated_text <- character()
  buffer <- character()
  current_event <- NULL
  current_data <- NULL

  stream_callback <- function(data) {
    lines <- strsplit(rawToChar(data), "\n")[[1]]

    for (line in lines) {
      parsed <- parse_sse_line(line)

      if (!is.null(parsed)) {
        if (parsed$type == "event") {
          current_event <<- parsed$value
        } else if (parsed$type == "data") {
          current_data <<- parsed$value
        } else if (parsed$type == "separator" && !is.null(current_event)) {
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
            if (!is.null(on_error)) on_error(event_data$error)
          }

          current_event <<- NULL
          current_data <<- NULL
        }
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
  curl::handle_setopt(handle, post = TRUE, postfields = body_json)

  curl::curl_fetch_stream(url, fun = stream_callback, handle = handle)

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

  if (httr::http_error(response)) {
    content <- httr::content(response, as = "text", encoding = "UTF-8")
    stop("Approve failed: ", content)
  }

  invisible(NULL)
}

shutdown_session <- function(client) {
  if (!client$session_active) {
    return(invisible(client))
  }

  url <- paste0(client$base_url, "/shutdown")

  tryCatch({
    httr::POST(url, httr::timeout(5))
  }, error = function(e) {
    warning("Failed to shutdown session gracefully: ", e$message)
  })

  client$session_active <- FALSE
  invisible(client)
}

check_health <- function(client) {
  url <- paste0(client$base_url, "/health")

  tryCatch({
    response <- httr::GET(url, httr::timeout(2))

    if (httr::http_error(response)) {
      return(list(status = "error", message = "Server returned error"))
    }

    httr::content(response, as = "parsed")
  }, error = function(e) {
    list(status = "error", message = e$message)
  })
}

`%||%` <- function(a, b) if (is.null(a)) b else a
