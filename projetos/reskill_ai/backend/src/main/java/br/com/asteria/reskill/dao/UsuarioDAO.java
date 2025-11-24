package br.com.asteria.reskill.dao;

import br.com.asteria.reskill.entity.Usuario;
import br.com.asteria.reskill.factory.ConnectionFactory;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class UsuarioDAO {

    public Usuario inserir(Usuario usuario) throws SQLException {
        String sql = "INSERT INTO USUARIO (ID_USUARIO, NOME, IDADE, AREA_INTERESSE, NIVEL_FORMACAO, HABILIDADES, OBJETIVO_PROFISSIONAL) " +
                     "VALUES (SEQ_USUARIO.NEXTVAL, ?, ?, ?, ?, ?, ?)";

        try (Connection con = ConnectionFactory.getConnection();
             PreparedStatement ps = con.prepareStatement(sql, new String[] { "ID_USUARIO" })) {

            ps.setString(1, usuario.getNome());
            ps.setObject(2, usuario.getIdade(), Types.INTEGER);
            ps.setString(3, usuario.getAreaInteresse());
            ps.setString(4, usuario.getNivelFormacao());
            ps.setString(5, usuario.getHabilidades());
            ps.setString(6, usuario.getObjetivoProfissional());

            ps.executeUpdate();

            try (ResultSet rs = ps.getGeneratedKeys()) {
                if (rs.next()) {
                    usuario.setIdUsuario(rs.getLong(1));
                }
            }
        }
        return usuario;
    }

    public Usuario buscarPorId(Long id) throws SQLException {
        String sql = "SELECT ID_USUARIO, NOME, IDADE, AREA_INTERESSE, NIVEL_FORMACAO, HABILIDADES, OBJETIVO_PROFISSIONAL " +
                     "FROM USUARIO WHERE ID_USUARIO = ?";
        try (Connection con = ConnectionFactory.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setLong(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    Usuario u = new Usuario();
                    u.setIdUsuario(rs.getLong("ID_USUARIO"));
                    u.setNome(rs.getString("NOME"));
                    java.math.BigDecimal idadeBd = rs.getBigDecimal("IDADE");
                        if (idadeBd != null) {
                            u.setIdade(idadeBd.intValue());
                            } else {
                             u.setIdade(null);
                                    }
                    u.setAreaInteresse(rs.getString("AREA_INTERESSE"));
                    u.setNivelFormacao(rs.getString("NIVEL_FORMACAO"));
                    u.setHabilidades(rs.getString("HABILIDADES"));
                    u.setObjetivoProfissional(rs.getString("OBJETIVO_PROFISSIONAL"));
                    return u;
                }
            }
        }
        return null;
    }

    public List<Usuario> listarTodos() throws SQLException {
        List<Usuario> lista = new ArrayList<>();
        String sql = "SELECT ID_USUARIO, NOME, IDADE, AREA_INTERESSE, NIVEL_FORMACAO, HABILIDADES, OBJETIVO_PROFISSIONAL FROM USUARIO";

        try (Connection con = ConnectionFactory.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                Usuario u = new Usuario();
                u.setIdUsuario(rs.getLong("ID_USUARIO"));
                u.setNome(rs.getString("NOME"));
                java.math.BigDecimal idadeBd = rs.getBigDecimal("IDADE");
if (idadeBd != null) {
    u.setIdade(idadeBd.intValue());
} else {
    u.setIdade(null);
}
                u.setAreaInteresse(rs.getString("AREA_INTERESSE"));
                u.setNivelFormacao(rs.getString("NIVEL_FORMACAO"));
                u.setHabilidades(rs.getString("HABILIDADES"));
                u.setObjetivoProfissional(rs.getString("OBJETIVO_PROFISSIONAL"));
                lista.add(u);
            }
        }
        return lista;
    }
}