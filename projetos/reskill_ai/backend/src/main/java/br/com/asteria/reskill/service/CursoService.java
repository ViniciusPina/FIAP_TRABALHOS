package br.com.asteria.reskill.service;

import br.com.asteria.reskill.dao.CursoDAO;
import br.com.asteria.reskill.entity.Curso;

import java.sql.SQLException;
import java.util.List;

public class CursoService {

    private final CursoDAO dao = new CursoDAO();

    public Curso criar(Curso c) throws SQLException {
        return dao.inserir(c);
    }

    public List<Curso> listarTodos() throws SQLException {
        return dao.listarTodos();
    }
}
