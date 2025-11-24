package br.com.asteria.reskill.service;

import br.com.asteria.reskill.dao.UsuarioDAO;
import br.com.asteria.reskill.entity.Usuario;

import java.sql.SQLException;
import java.util.List;

public class UsuarioService {

    private final UsuarioDAO dao = new UsuarioDAO();

    public Usuario criar(Usuario usuario) throws SQLException {
        return dao.inserir(usuario);
    }

    public Usuario buscarPorId(Long id) throws SQLException {
        return dao.buscarPorId(id);
    }

    public List<Usuario> listarTodos() throws SQLException {
        return dao.listarTodos();
    }
}
