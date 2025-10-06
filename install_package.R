if (!require("devtools", quietly = TRUE)) {
  install.packages("devtools", repos = "https://cloud.r-project.org")
}

devtools::install_local(
  "/Users/tylerlifke/Documents/r-studio-claude-code-addin",
  dependencies = FALSE,
  upgrade = "never",
  force = TRUE,
  quiet = TRUE
)

cat("Package updated successfully!\n")
