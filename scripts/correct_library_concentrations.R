suppressPackageStartupMessages({
  library(tidyverse)
  library(reshape2)
  library(gridExtra)
  library(xml2)
})

ggplot_theme <- theme(axis.line.y = element_line(size=.1,color = "black"),
                      axis.line.x = element_line(size=.1,color = "black"),
                      axis.text.x = element_text(angle = 45, hjust = 1, size=10, lineheight=0.2, color="black"),
                      panel.grid.major = element_line(color = "black"), 
                      legend.text=element_text(size=8), 
                      panel.background = element_rect(fill="white"), 
                      panel.grid.major.x = element_line(size=.1, color="grey"), 
                      panel.grid.major.y = element_blank(), plot.title = element_text(size=15))

args <- commandArgs(trailingOnly = TRUE)
run_completion_xml_filename <- args[1]
desired_cluster_density <- as.numeric(args[2])
read_count_filename <- args[3]
project <- args[4]

actual_cluster_density <- as.numeric(xml_text(xml_find_all(read_xml(run_completion_xml_filename), "ClusterDensity")))
cluster_correction_factor <- actual_cluster_density / desired_cluster_density

# Calculate correction factor per sample
read_count_df <- read.delim(read_count_filename)
if (!"cluster_correction_factor" %in% colnames(read_count_df)) {
  if (str_count(read_count_df$sample, "_")[1] == 6) {
    read_count_df <- read_count_df %>%
      separate(sample, sep = "_", c("project", "cell_type", "tissue_origin", "sequencing_type", "TBID", "sample", "sample_number")) %>%
      mutate(sample_number = str_remove(sample_number, "S")) 
  }
  if (!"library_group" %in% colnames(read_count_df)) {
    read_count_df <- read_count_df %>%
      mutate(library_group = 1)
  }
  if (actual_cluster_density > 290) {
    warning <- sprintf("warning: cluster density is %s thus concentration correction may not be accurate\n", actual_cluster_density)
    cat(warning)
    read_count_df <- read_count_df %>%
      mutate(notes = warning)
  }
  read_count_df <- read_count_df %>% 
    mutate(cluster_correction_factor = cluster_correction_factor) %>%
    group_by(library_group) %>%
    mutate(expected_percent = round((100 / length(sample)), 2), library_group_read_count = sum(read_count)) %>%
    ungroup() %>%
    mutate(read_percent = round((100 * read_count / library_group_read_count), 2)) %>%
    mutate(correction_factor = read_percent / expected_percent) %>%
    group_by(library_group) %>%
    mutate(corrected_initial_concentration = (cluster_correction_factor * correction_factor * initial_concentration)) %>%
    ungroup()
  write.table(read_count_df, read_count_filename, sep ="\t", quote = FALSE, row.names = FALSE, col.names = TRUE)
}

# Read count bar plot
read_fraction_barplot <- ggplot(read_count_df, aes(sample, read_percent, fill=library_group)) + 
  geom_bar(stat="identity") + ggtitle("Read percentage per sample") +
  geom_hline(aes(yintercept=expected_percent, color=library_group), linetype="dashed") +
  geom_text(aes(label=read_percent), hjust=-0.2, vjust=0.5, size=3.5) +
  geom_text(aes(0,expected_percent,label = sprintf("%s expected", expected_percent), hjust=-0.2, vjust = -1, color=library_group)) +
  annotate("text", x = 1, y = 90, label = sprintf("cluster density:\n%s actual", round(actual_cluster_density, 2))) +
  ggplot_theme + theme(legend.position="none") + ylim(0, 100) + coord_flip() # + facet_wrap(~ library_group) 

# Melt data for dotchart
melted_data <- melt(read_count_df[,c("sample","initial_concentration","corrected_initial_concentration", "read_count")], 
                             id.vars = c("sample", "read_count"), value.name = "concentration")

# Actual and corrected concentration dotchart
right_label <- melted_data %>% group_by(sample) %>% arrange(desc(concentration)) %>% top_n(1)
left_label <- melted_data %>% group_by(sample) %>% arrange(desc(concentration)) %>% slice(2)
concentration_dotchart <- ggplot(melted_data, aes(concentration, sample)) +
  geom_line(aes(group = sample)) + geom_point(aes(color = variable), size = 1.5) +
  geom_text(data = right_label, aes(color = variable, label = round(concentration, 2)), size = 3, hjust = -.5) +
  geom_text(data = left_label, aes(color = variable, label = round(concentration, 2)), size = 3, hjust = 1.5) +
  ggplot_theme + ggtitle("Initial and corrected concentrations per sample") + 
  scale_x_continuous(limits = c(0, max(melted_data$concentration)+2))

# Export read counts alongside 
pdf(sprintf("%s.fig_initial_concentration_corrections.pdf", project), width = 16, height = 8.5)
grid.arrange(read_fraction_barplot, concentration_dotchart, nrow = 1)
dev.off()
cat("Calculated and graphed corrected initial concentration\n")
