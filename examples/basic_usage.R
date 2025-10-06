library(claudeACP)

example_interactive_session <- function() {
  claude_acp_addin()
}

example_programmatic_usage <- function() {
  client <- ACPClient$new(
    command = "npx",
    args = c("@zed-industries/claude-code-acp"),
    env = c(paste0("ANTHROPIC_API_KEY=", Sys.getenv("ANTHROPIC_API_KEY")))
  )

  setup_client_methods(client)

  promises::then(
    client$initialize_agent(list(
      protocolVersion = 0.1,
      clientCapabilities = list(
        fs = list(readTextFile = TRUE, writeTextFile = TRUE),
        terminal = TRUE
      )
    )),
    onFulfilled = function(init_result) {
      print("Agent initialized successfully")
      print(init_result)

      promises::then(
        client$create_session(),
        onFulfilled = function(session_result) {
          print("Session created:")
          print(session_result)

          promises::then(
            client$send_prompt("Write a simple R function that adds two numbers"),
            onFulfilled = function(response) {
              print("Agent response:")
              print(response)

              client$shutdown()
            }
          )
        }
      )
    },
    onRejected = function(error) {
      print("Error occurred:")
      print(error)
      client$shutdown()
    }
  )
}

example_custom_agent <- function() {
  client <- ACPClient$new(
    command = "gemini",
    args = c("--experimental-acp"),
    env = c(paste0("GEMINI_API_KEY=", Sys.getenv("GEMINI_API_KEY")))
  )

  setup_client_methods(client)

  promises::then(
    client$initialize_agent(list(
      protocolVersion = 0.1,
      clientCapabilities = list(
        fs = list(readTextFile = TRUE, writeTextFile = TRUE),
        terminal = TRUE
      )
    )),
    onFulfilled = function(result) {
      print("Gemini agent initialized!")
      client$shutdown()
    }
  )
}
