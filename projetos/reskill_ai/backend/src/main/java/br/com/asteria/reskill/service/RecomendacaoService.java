package br.com.asteria.reskill.service;

import br.com.asteria.reskill.dao.RecomendacaoDAO;
import br.com.asteria.reskill.entity.Recomendacao;

import java.sql.SQLException;
import java.util.List;

public class RecomendacaoService {

    private final RecomendacaoDAO dao = new RecomendacaoDAO();

    public void salvar(Recomendacao r) throws SQLException {
        dao.salvar(r);
    }

    public List<Recomendacao> listarPorUsuario(Long idUsuario) throws SQLException {
        return dao.listarPorUsuario(idUsuario);
    }
}
