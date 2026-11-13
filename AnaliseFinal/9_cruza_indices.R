# Passo 9: cruza as quebras aceitas de NDVI, EVI e NDMI em cada area amostral.
# Duas quebras batem quando estao a ate tolerancia_dias uma da outra e tem a mesma direcao;
# cada grupo tem no maximo uma quebra por indice
# Rodar dentro desta pasta, depois do passo 8: Rscript 9_cruza_indices.R
# Saida: resultados/indices/cruzamento_lite.csv

source("parametros.R")

indices <- c("NDVI", "EVI", "NDMI")
arquivos <- c(NDVI = "resultados/eventos_buffer.csv",
              EVI = "resultados/indices/EVI/eventos_buffer.csv",
              NDMI = "resultados/indices/NDMI/eventos_buffer.csv")

eventos <- do.call(rbind, lapply(indices, function(i) data.frame(read.csv(arquivos[[i]]), indice = i)))
eventos <- eventos[eventos$aceito, ]
eventos$data <- as.Date(eventos$data)

# agrupa as quebras de uma area, comecando pelos pares mais proximos
agrupa <- function(ev) {
  n <- nrow(ev)
  grupo <- seq_len(n)
  if (n > 1) {
    pares <- t(combn(n, 2))
    pares <- pares[order(abs(as.numeric(ev$data[pares[, 1]] - ev$data[pares[, 2]]))), , drop = FALSE]
    for (l in seq_len(nrow(pares))) {
      i <- pares[l, 1]; j <- pares[l, 2]
      if (grupo[i] == grupo[j]) next
      juntos <- which(grupo %in% c(grupo[i], grupo[j]))
      if (anyDuplicated(ev$indice[juntos]) > 0) next
      if (length(unique(ev$direcao[juntos])) > 1) next
      if (as.numeric(diff(range(ev$data[juntos]))) > tolerancia_dias) next
      grupo[juntos] <- grupo[i]
    }
  }
  grupo
}

# valor de um indice no grupo (NA se o indice nao tem a quebra)
pega <- function(g, indice, coluna) {
  v <- g[[coluna]][g$indice == indice]
  if (length(v) == 0) NA else v
}

linhas <- list()
for (b in sort(unique(eventos$buffer))) {
  ev <- eventos[eventos$buffer == b, ]
  ev$grupo <- agrupa(ev)
  for (id in unique(ev$grupo)) {
    g <- ev[ev$grupo == id, ]
    l <- data.frame(buffer = b, direcao = g$direcao[1], n_indices = nrow(g),
                    indices = paste(indices[indices %in% g$indice], collapse = "+"),
                    amplitude_dias = as.numeric(diff(range(g$data))))
    for (i in indices) {
      l[[paste0("data_", i)]] <- as.character(pega(g, i, "data"))
      l[[paste0("magnitude_", i)]] <- pega(g, i, "magnitude_mediana")
    }
    linhas[[length(linhas) + 1]] <- l
  }
}
cruzado <- do.call(rbind, linhas)
cruzado <- cruzado[order(cruzado$buffer, pmin(cruzado$data_NDVI, cruzado$data_EVI, cruzado$data_NDMI, na.rm = TRUE)), ]
write.csv(cruzado, "resultados/indices/cruzamento_lite.csv", row.names = FALSE)

cat("Quebras aceitas:\n")
print(table(eventos$indice)[indices])
cat("\nGrupos com a quebra do NDVI, por combinacao de indices:\n")
print(table(cruzado$indices[!is.na(cruzado$data_NDVI)]))
