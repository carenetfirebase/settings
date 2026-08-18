"""CLI entry point. `invest --help` after `pip install -e .`."""

import typer
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from invest import __version__
from invest.db.session import get_engine

app = typer.Typer(help="Zero-cost, institutional-style investment research platform.")
db_app = typer.Typer(help="Database utilities.")
app.add_typer(db_app, name="db")


@app.command()
def version() -> None:
    """Print the installed invest version."""
    typer.echo(__version__)


@db_app.command("check")
def db_check() -> None:
    """Verify the configured database is reachable."""
    try:
        with get_engine().connect() as conn:
            conn.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        typer.echo(f"DATABASE UNREACHABLE: {exc}", err=True)
        raise typer.Exit(code=1) from exc
    typer.echo("Database connection OK.")


if __name__ == "__main__":
    app()
