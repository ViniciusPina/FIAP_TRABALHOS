package br.com.asteria.reskill.entity;

public class Usuario {
    private Long idUsuario;
    private String nome;
    private Integer idade;
    private String areaInteresse;
    private String nivelFormacao;
    private String habilidades;
    private String objetivoProfissional;

    public Long getIdUsuario() { return idUsuario; }
    public void setIdUsuario(Long idUsuario) { this.idUsuario = idUsuario; }

    public String getNome() { return nome; }
    public void setNome(String nome) { this.nome = nome; }

    public Integer getIdade() { return idade; }
    public void setIdade(Integer idade) { this.idade = idade; }

    public String getAreaInteresse() { return areaInteresse; }
    public void setAreaInteresse(String areaInteresse) { this.areaInteresse = areaInteresse; }

    public String getNivelFormacao() { return nivelFormacao; }
    public void setNivelFormacao(String nivelFormacao) { this.nivelFormacao = nivelFormacao; }

    public String getHabilidades() { return habilidades; }
    public void setHabilidades(String habilidades) { this.habilidades = habilidades; }

    public String getObjetivoProfissional() { return objetivoProfissional; }
    public void setObjetivoProfissional(String objetivoProfissional) { this.objetivoProfissional = objetivoProfissional; }
}
