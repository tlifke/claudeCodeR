ACPWebSocketClient <- R6::R6Class("ACPWebSocketClient",
  public = list(
    initialize = function(ws_url, on_message = NULL, on_error = NULL) {
      private$ws_url <- ws_url
      private$on_message_callback <- on_message
      private$on_error_callback <- on_error
      private$request_id <- 1
      private$pending_requests <- list()
      private$connected <- FALSE
    },

    connect = function() {
      if (private$connected) {
        warning("WebSocket already connected")
        return(invisible(self))
      }

      private$ws <- websocket::WebSocket$new(private$ws_url)

      private$ws$onOpen(function(event) {
        message("WebSocket connected to ", private$ws_url)
        private$connected <- TRUE
      })

      private$ws$onMessage(function(event) {
        private$handle_message(event$data)
      })

      private$ws$onError(function(event) {
        message("WebSocket error: ", event$message)
        if (!is.null(private$on_error_callback)) {
          private$on_error_callback(event$message)
        }
      })

      private$ws$onClose(function(event) {
        message("WebSocket closed")
        private$connected <- FALSE
      })

      invisible(self)
    },

    send_request = function(method, params = list()) {
      if (!private$connected) {
        stop("WebSocket not connected. Call connect() first.")
      }

      request_id <- private$request_id
      private$request_id <- private$request_id + 1

      request <- list(
        jsonrpc = "2.0",
        id = request_id,
        method = method,
        params = params
      )

      message_json <- jsonlite::toJSON(request, auto_unbox = TRUE)
      private$ws$send(message_json)

      promise <- promises::promise(function(resolve, reject) {
        private$pending_requests[[as.character(request_id)]] <- list(
          resolve = resolve,
          reject = reject,
          method = method
        )
      })

      promise
    },

    send_notification = function(method, params = list()) {
      if (!private$connected) {
        stop("WebSocket not connected. Call connect() first.")
      }

      notification <- list(
        jsonrpc = "2.0",
        method = method,
        params = params
      )

      message_json <- jsonlite::toJSON(notification, auto_unbox = TRUE)
      private$ws$send(message_json)

      invisible(self)
    },

    is_connected = function() {
      private$connected
    },

    close = function() {
      if (!is.null(private$ws)) {
        private$ws$close()
        private$connected <- FALSE
      }
      invisible(self)
    }
  ),

  private = list(
    ws_url = NULL,
    ws = NULL,
    request_id = 1,
    pending_requests = list(),
    on_message_callback = NULL,
    on_error_callback = NULL,
    connected = FALSE,

    handle_message = function(data) {
      message_obj <- tryCatch({
        jsonlite::fromJSON(data, simplifyVector = FALSE)
      }, error = function(e) {
        message("Failed to parse WebSocket message: ", e$message)
        message("Raw data: ", substr(data, 1, 200))
        return(NULL)
      })

      if (is.null(message_obj)) {
        return(invisible(NULL))
      }

      if (!is.null(message_obj$id)) {
        request_id <- as.character(message_obj$id)

        if (request_id %in% names(private$pending_requests)) {
          pending <- private$pending_requests[[request_id]]

          if (!is.null(message_obj$error)) {
            error_msg <- if (is.list(message_obj$error)) {
              message_obj$error$message %||% "Unknown error"
            } else {
              as.character(message_obj$error)
            }
            message("Request ", request_id, " (", pending$method, ") failed: ", error_msg)
            pending$reject(error_msg)
          } else {
            message("Request ", request_id, " (", pending$method, ") succeeded")
            pending$resolve(message_obj$result)
          }

          private$pending_requests[[request_id]] <- NULL
        } else {
          message("Received response for unknown request ID: ", request_id)
        }
      }

      if (!is.null(private$on_message_callback)) {
        private$on_message_callback(message_obj)
      }

      invisible(NULL)
    }
  )
)
