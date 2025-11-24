package br.com.asteria.reskill.controller;

import br.com.asteria.reskill.entity.Curso;
import br.com.asteria.reskill.service.CursoService;

import javax.ws.rs.*;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;
import java.sql.SQLException;
import java.util.List;

@Path("/cursos")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class CursoController {

    private final CursoService service = new CursoService();

    @POST
    public Response criar(Curso c) {
        try {
            Curso criado = service.criar(c);
            return Response.status(Response.Status.CREATED).entity(criado).build();
        } catch (SQLException e) {
            return Response.serverError().entity(e.getMessage()).build();
        }
    }

    @GET
    public Response listar() {
        try {
            List<Curso> lista = service.listarTodos();
            return Response.ok(lista).build();
        } catch (SQLException e) {
            return Response.serverError().entity(e.getMessage()).build();
        }
    }
}
