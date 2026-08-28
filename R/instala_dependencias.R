# Instala os pacotes R necessarios. Rode uma vez.
#   Rscript R/instala_dependencias.R

pacotes <- c("zoo", "bfast", "strucchangeRcpp")
faltando <- setdiff(pacotes, rownames(installed.packages()))

if (length(faltando) == 0) {
  cat("todas as dependencias ja estao instaladas\n")
} else {
  cat("instalando:", paste(faltando, collapse = ", "), "\n")
  install.packages(faltando, repos = "https://cloud.r-project.org")
}

for (p in pacotes) {
  ok <- requireNamespace(p, quietly = TRUE)
  cat(sprintf("  %-18s %s\n", p, if (ok) "ok" else "FALHOU"))
}
