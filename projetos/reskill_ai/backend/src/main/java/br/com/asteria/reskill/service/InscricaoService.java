package br.com.asteria.reskill.service;

import br.com.asteria.reskill.dao.InscricaoDAO;
import br.com.asteria.reskill.entity.Inscricao;

import java.sql.SQLException;
import java.util.List;

public class InscricaoService {

    private final InscricaoDAO dao = new InscricaoDAO();

    public Inscricao criar(Inscricao i) throws SQLException {
        return dao.inserir(i);
    }

    public List<Inscricao> listarPorUsuario(Long idUsuario) throws SQLException {
        return dao.listarPorUsuario(idUsuario);
    }
}
