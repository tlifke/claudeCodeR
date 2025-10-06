get_editor_context <- function() {
  if (!rstudioapi::isAvailable()) {
    stop("RStudio API is not available. This package requires RStudio.")
  }

  context <- rstudioapi::getActiveDocumentContext()

  list(
    path = if (nchar(context$path) > 0) normalizePath(context$path, mustWork = FALSE) else NULL,
    content = paste(context$contents, collapse = "\n"),
    selection = if (length(context$selection) > 0) {
      sel <- context$selection[[1]]
      list(
        text = sel$text,
        range = list(
          start = list(line = sel$range$start[[1]], character = sel$range$start[[2]]),
          end = list(line = sel$range$end[[1]], character = sel$range$end[[2]])
        )
      )
    } else {
      NULL
    },
    language = context$id
  )
}

insert_code <- function(code, location = NULL) {
  if (!rstudioapi::isAvailable()) {
    stop("RStudio API is not available. This package requires RStudio.")
  }

  if (is.null(location)) {
    context <- rstudioapi::getActiveDocumentContext()
    if (length(context$selection) > 0) {
      location <- context$selection[[1]]$range
    } else {
      rstudioapi::insertText(code)
      return(invisible(TRUE))
    }
  }

  rstudioapi::insertText(location, code)
  invisible(TRUE)
}

replace_document <- function(code) {
  if (!rstudioapi::isAvailable()) {
    stop("RStudio API is not available. This package requires RStudio.")
  }

  context <- rstudioapi::getActiveDocumentContext()
  rstudioapi::setDocumentContents(code, id = context$id)
  invisible(TRUE)
}

get_project_files <- function() {
  if (!rstudioapi::isAvailable()) {
    return(character())
  }

  project_path <- tryCatch({
    rstudioapi::getActiveProject()
  }, error = function(e) NULL)

  if (is.null(project_path)) {
    return(character())
  }

  files <- list.files(project_path, recursive = TRUE, full.names = TRUE)
  normalizePath(files, mustWork = FALSE)
}

normalize_path <- function(path) {
  if (is.null(path) || nchar(path) == 0) {
    return(NULL)
  }

  if (!startsWith(path, "/") && !grepl("^[A-Za-z]:", path)) {
    project_path <- tryCatch({
      rstudioapi::getActiveProject()
    }, error = function(e) getwd())

    path <- file.path(project_path, path)
  }

  normalizePath(path, mustWork = FALSE)
}
