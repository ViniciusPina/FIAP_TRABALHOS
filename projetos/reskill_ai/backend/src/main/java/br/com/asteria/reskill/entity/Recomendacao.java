package br.com.asteria.reskill.entity;

public class Recomendacao {
    private Long idRecomendacao;
    private Long idUsuario;
    private Long idCurso;
    private Double score;
    private String tipoRecomendacao;

    // --- NOVOS CAMPOS (Detalhes do Curso para exibir no Front) ---
    private String nomeCurso;
    private String categoriaCurso;
    private String nivelCurso;
    private Integer cargaHorariaCurso;
    private String linkCurso;

    // Getters e Setters normais
    public Long getIdRecomendacao() { return idRecomendacao; }
    public void setIdRecomendacao(Long idRecomendacao) { this.idRecomendacao = idRecomendacao; }
    public Long getIdUsuario() { return idUsuario; }
    public void setIdUsuario(Long idUsuario) { this.idUsuario = idUsuario; }
    public Long getIdCurso() { return idCurso; }
    public void setIdCurso(Long idCurso) { this.idCurso = idCurso; }
    public Double getScore() { return score; }
    public void setScore(Double score) { this.score = score; }
    public String getTipoRecomendacao() { return tipoRecomendacao; }
    public void setTipoRecomendacao(String tipoRecomendacao) { this.tipoRecomendacao = tipoRecomendacao; }

    // Getters e Setters dos Novos Campos
    public String getNomeCurso() { return nomeCurso; }
    public void setNomeCurso(String nomeCurso) { this.nomeCurso = nomeCurso; }
    public String getCategoriaCurso() { return categoriaCurso; }
    public void setCategoriaCurso(String categoriaCurso) { this.categoriaCurso = categoriaCurso; }
    public String getNivelCurso() { return nivelCurso; }
    public void setNivelCurso(String nivelCurso) { this.nivelCurso = nivelCurso; }
    public Integer getCargaHorariaCurso() { return cargaHorariaCurso; }
    public void setCargaHorariaCurso(Integer cargaHorariaCurso) { this.cargaHorariaCurso = cargaHorariaCurso; }
    public String getLinkCurso() { return linkCurso; }
    public void setLinkCurso(String linkCurso) { this.linkCurso = linkCurso; }
}