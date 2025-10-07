# Load ggplot2
library(ggplot2)

# Create sample data
data <- data.frame(
  x = rnorm(100),
  y = rnorm(100)
)

# Create scatterplot
plot <- ggplot(data, aes(x = x, y = y)) +
  geom_point(color = "steelblue", size = 3, alpha = 0.6) +
  labs(
    title = "Sample Scatterplot",
    x = "X Variable",
    y = "Y Variable"
  ) +
  theme_minimal()

# Display the plot
print(plot)
