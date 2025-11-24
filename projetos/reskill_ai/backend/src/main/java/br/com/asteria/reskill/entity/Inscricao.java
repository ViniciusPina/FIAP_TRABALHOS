package br.com.asteria.reskill.entity;

public class Inscricao {
    private Long idInscricao;
    private Long idUsuario;
    private Long idCurso;
    private Integer progresso;
    private Integer avaliacao;

    public Long getIdInscricao() { return idInscricao; }
    public void setIdInscricao(Long idInscricao) { this.idInscricao = idInscricao; }

    public Long getIdUsuario() { return idUsuario; }
    public void setIdUsuario(Long idUsuario) { this.idUsuario = idUsuario; }

    public Long getIdCurso() { return idCurso; }
    public void setIdCurso(Long idCurso) { this.idCurso = idCurso; }

    public Integer getProgresso() { return progresso; }
    public void setProgresso(Integer progresso) { this.progresso = progresso; }

    public Integer getAvaliacao() { return avaliacao; }
    public void setAvaliacao(Integer avaliacao) { this.avaliacao = avaliacao; }
}
