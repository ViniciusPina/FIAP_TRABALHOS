# RE:Skill AI - Engine de Recomendação V6 (Híbrido: Sniper + ML)
# Combina regras de negócio (palavras-chave) com previsão de IA (Random Forest).

# --- 0. INSTALAÇÃO DE PACOTES ---
pacotes <- c("DBI", "odbc", "dplyr", "randomForest")
novos_pacotes <- pacotes[!(pacotes %in% installed.packages()[,"Package"])]
if(length(novos_pacotes)) install.packages(novos_pacotes)

library(DBI)
library(odbc)
library(dplyr)
library(randomForest)

cat(" Iniciando Engine de Recomendação V6...\n")

# --- 1. CONEXÃO ---
# Certifique-se que o DSN 'ORACLE_FIAP' está configurado no Windows
con <- dbConnect(odbc(), dsn = "ORACLE_FIAP", uid = "RM558270", pwd = "181199")
cat("conectado ao Oracle via ODBC.\n")

# --- 2. LEITURA DE DADOS ---
usuarios   <- dbGetQuery(con, "SELECT ID_USUARIO, AREA_INTERESSE, NIVEL_FORMACAO, HABILIDADES FROM USUARIO")
cursos     <- dbGetQuery(con, "SELECT ID_CURSO, NOME, CATEGORIA, NIVEL FROM CURSO")
inscricoes <- dbGetQuery(con, "SELECT ID_USUARIO, ID_CURSO, PROGRESSO, AVALIACAO FROM INSCRICAO")

cat(sprintf(" Dados carregados: %d usuários, %d cursos, %d inscrições.\n", nrow(usuarios), nrow(cursos), nrow(inscricoes)))

if (nrow(usuarios) == 0 || nrow(cursos) == 0) {
  cat("Sem dados suficientes para rodar.\n")
} else {
  
  # --- 3. TREINAMENTO DO MODELO DE ML (RANDOM FOREST) ---
  cat("Preparando modelo de Machine Learning...\n")
  
  # Prepara o dataset para treino
  ml_data <- merge(inscricoes, usuarios, by = "ID_USUARIO")
  ml_data <- merge(ml_data, cursos, by = "ID_CURSO")
  
  # Define o alvo (Target): Preferência por Avaliação, se não tiver, usa Progresso
  if ("AVALIACAO" %in% colnames(ml_data) && sum(!is.na(ml_data$AVALIACAO)) > 5) {
    ml_data$TARGET <- as.numeric(ml_data$AVALIACAO) / 5 # Normaliza 0-1
    cat("Target definido: AVALIAÇÃO\n")
  } else if ("PROGRESSO" %in% colnames(ml_data)) {
    ml_data$TARGET <- as.numeric(ml_data$PROGRESSO) / 100 # Normaliza 0-1
    cat("Target definido: PROGRESSO\n")
  } else {
    ml_data$TARGET <- NA
  }
  
  # Só treina se tiver dados suficientes (mínimo 10 registros com alvo)
  usar_ml <- sum(!is.na(ml_data$TARGET)) >= 10
  modelo_rf <- NULL
  
  if (usar_ml) {
    tryCatch({
      # Trata dados faltantes com a média ou moda
      ml_data$TARGET[is.na(ml_data$TARGET)] <- 0.5
      
      # Treina o modelo para prever o 'TARGET' baseado no Curso e Nível
      set.seed(42)
      modelo_rf <- randomForest(TARGET ~ ID_CURSO + NIVEL + CATEGORIA, 
                                data = ml_data, ntree = 100, na.action = na.roughfix)
      cat("odelo Random Forest treinado com sucesso.\n")
    }, error = function(e) {
      cat("rro ao treinar modelo ML (usando fallback Sniper): ", e$message, "\n")
      usar_ml <- FALSE
    })
  } else {
    cat(" Dados insuficientes para ML. Ativando modo puramente Sniper.\n")
  }
  
  # --- 4. FUNÇÃO SNIPER (REGRAS DE NEGÓCIO) ---
  calcular_score_sniper <- function(usuario, cursos_df) {
    u_area <- tolower(usuario$AREA_INTERESSE)
    u_skills <- unlist(strsplit(tolower(usuario$HABILIDADES), "[,;]\\s*"))
    u_skills <- u_skills[u_skills != ""]
    
    scores <- numeric(nrow(cursos_df))
    
    for(i in 1:nrow(cursos_df)) {
      c_cat <- tolower(cursos_df$CATEGORIA[i])
      c_nome <- tolower(cursos_df$NOME[i])
      
      # Match Área (0.4)
      match_area <- ifelse(grepl(u_area, c_cat, fixed = TRUE), 0.4, 0.0)
      
      # Match Palavra-Chave (0.4)
      match_keyword <- 0
      for(skill in u_skills) {
        if(grepl(skill, c_nome, fixed = TRUE)) {
          match_keyword <- 0.4
          break
        }
      }
      
      # Match Nível (0.1)
      match_nivel <- ifelse(tolower(usuario$NIVEL_FORMACAO) == tolower(cursos_df$NIVEL[i]), 0.1, 0.0)
      
      # Base (0.1)
      scores[i] <- match_area + match_keyword + match_nivel + 0.1
    }
    return(pmin(scores, 0.99))
  }
  
  # --- 5. EXECUÇÃO E GRAVAÇÃO ---
  dbExecute(con, "DELETE FROM RECOMENDACAO")
  total_gravado <- 0
  
  for (i in seq_len(nrow(usuarios))) {
    u <- usuarios[i, ]
    
    # A. Calcula Score Sniper (Regras)
    scores_sniper <- calcular_score_sniper(u, cursos)
    
    # B. Calcula Score ML (Previsão), se disponível
    scores_final <- scores_sniper # Padrão é usar só o sniper
    
    if (usar_ml) {
      # Cria dataset fictício para o modelo prever o interesse deste usuário em TODOS os cursos
      pred_data <- data.frame(
        ID_CURSO = cursos$ID_CURSO,
        NIVEL = cursos$NIVEL,
        CATEGORIA = cursos$CATEGORIA
      )
      # Faz a previsão
      predicao <- predict(modelo_rf, pred_data)
      
      # Combina: 60% ML + 40% Regras (Híbrido)
      scores_final <- (predicao * 0.6) + (scores_sniper * 0.4)
    }
    
    # Remove cursos já feitos
    cursos_feitos <- subset(inscricoes, ID_USUARIO == u$ID_USUARIO)$ID_CURSO
    temp_df <- data.frame(ID_CURSO = cursos$ID_CURSO, SCORE = scores_final)
    if (length(cursos_feitos) > 0) {
      temp_df <- temp_df[!temp_df$ID_CURSO %in% cursos_feitos, ]
    }
    
    # Top 5
    temp_df <- temp_df[order(-temp_df$SCORE), ]
    top_recs <- head(temp_df, 5)
    
    if (nrow(top_recs) > 0) {
      for (j in seq_len(nrow(top_recs))) {
        row <- top_recs[j, ]
        
        # Rótulos Inteligentes
        tipo <- "Exploração"
        if (usar_ml && row$SCORE >= 0.8) tipo <- "Recomendação por IA"
        else if (row$SCORE >= 0.8) tipo <- "Match Perfeito"
        else if (row$SCORE >= 0.5) tipo <- "Recomendado"
        
        dbExecute(con, 
                  "INSERT INTO RECOMENDACAO (ID_RECOMENDACAO, ID_USUARIO, ID_CURSO, SCORE, TIPO_RECOMENDACAO) VALUES (SEQ_RECOMENDACAO.NEXTVAL, ?, ?, ?, ?)",
                  params = list(u$ID_USUARIO, row$ID_CURSO, round(row$SCORE, 2), tipo)
        )
        total_gravado <- total_gravado + 1
      }
    }
  }
  cat(sprintf("🏁 Finalizado! %d recomendações geradas e salvas.\n", total_gravado))
}
dbDisconnect(con)