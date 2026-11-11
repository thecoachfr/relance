"""Tests hors Home Assistant de `aiguillage_page` (page d'un lien partagé, règle X du tri).

Pages fictives uniquement (dépôt public)."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import aiguillage_page as p  # noqa: E402

PARTAGE = "📩 Message partagé\nUn marché de Noël revient en décembre\nhttps://exemple-sorties.fr/paris/marche-noel/\n👀 À voir"

ARTICLE = """<!doctype html><html><head><title>Marché de Noël | Exemple</title>
<meta property="og:title" content="Le marché de Noël revient en décembre">
<meta name="description" content="La 3e édition du Marché Exemple aura lieu les 5 et 6 décembre 2026.">
<script type="application/ld+json">{"@type": "NewsArticle", "headline": "x"}</script>
<style>p { color: red }</style></head>
<body><header><nav>Menu Sorties Restos</nav></header>
<article><h1>Le marché de Noël revient</h1><p>Plus de 80 stands&nbsp;d’artisanat.</p>
<script>var pub = 1;</script><aside>Lire aussi : autre chose</aside>
<p><strong>Marché Exemple</strong><br><strong>Salle Exemple</strong><br>
<strong>12, rue de l’Exemple &ndash; Paris 12</strong><br>Samedi 5 et dimanche 6 décembre 2026 de 12h à 19h</p>
</article><footer>Mentions légales</footer></body></html>"""


def test_lien_a_lire():
    assert p.lien_a_lire({"notes": PARTAGE}) == "https://exemple-sorties.fr/paris/marche-noel/"
    assert p.lien_a_lire({"notes": "📩 Message partagé — titre à revoir\nVoir https://exemple.fr/a."}) == \
        "https://exemple.fr/a"
    # Pas partagée, déjà un lieu, faite, ou lien traité ailleurs : rien.
    assert p.lien_a_lire({"notes": "https://exemple.fr/a"}) is None
    assert p.lien_a_lire({"notes": PARTAGE, "lieu": {"nom": "Salle Exemple"}}) is None
    assert p.lien_a_lire({"notes": PARTAGE, "fait": True}) is None
    assert p.lien_a_lire({"notes": "📩 Message partagé\nhttps://www.youtube.com/watch?v=x"}) is None
    assert p.lien_a_lire({"notes": "📩 Message partagé\nhttps://maps.apple.com/?q=x\nhttps://exemple.fr/b"}) == \
        "https://exemple.fr/b"


def test_extraire_article():
    page = p.extraire(ARTICLE, "https://exemple-sorties.fr/x")
    assert page["titre"] == "Le marché de Noël revient en décembre"
    assert page["description"].startswith("La 3e édition")
    assert "evenements" not in page
    texte = page["texte"]
    assert "12, rue de l’Exemple – Paris 12" in texte
    assert "Samedi 5 et dimanche 6 décembre 2026 de 12h à 19h" in texte
    assert "Plus de 80 stands d’artisanat." in texte
    for absent in ("Menu", "Mentions", "var pub", "Lire aussi", "color"):
        assert absent not in texte


def test_texte_hors_article_et_trop_long():
    page = p.extraire("<html><body><p>" + "début " + "x" * 9000 + "</p><p>Infos pratiques</p></body></html>")
    assert len(page["texte"]) <= p.TEXTE_MAX + 10
    assert page["texte"].startswith("début") and page["texte"].endswith("Infos pratiques")
    assert "[…]" in page["texte"]
    assert p.extraire("") == {}


def test_evenements_jsonld():
    html = """<script type="application/ld+json">{"@context": "https://schema.org", "@graph": [
      {"@type": "WebPage"},
      {"@type": ["MusicEvent"], "name": "Concert Exemple", "startDate": "2026-12-05T20:00",
       "endDate": "2026-12-05T23:00", "location": {"@type": "Place", "name": "Salle Exemple",
       "address": {"streetAddress": "12 rue de l'Exemple", "postalCode": "75012", "addressLocality": "Paris"}}}]}
    </script><script type="application/ld+json">pas du json</script>
    <script type="application/ld+json">[{"@type": "Event", "name": "Expo", "location": "Musée Exemple"}]</script>"""
    assert p.extraire(html)["evenements"] == [
        {"nom": "Concert Exemple", "debut": "2026-12-05T20:00", "fin": "2026-12-05T23:00", "lieu": "Salle Exemple",
         "adresse": "12 rue de l'Exemple, 75012 Paris"},
        {"nom": "Expo", "lieu": "Musée Exemple"},
    ]


def test_page_mal_formee():
    page = p.extraire("<html><body><article><p>Texte <b>sans fin</article></div></span><p>suite")
    assert "Texte sans fin" in page["texte"]


class _Reponse:
    def __init__(self, statut, type_, corps, url="https://exemple.fr/final"):
        self.status_code, self.headers, self._corps, self.url = statut, {"content-type": type_}, corps, url
        self.encoding = "utf-8"

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def iter_bytes(self):
        yield self._corps


class _Client:
    def __init__(self, reponse=None, erreur=None):
        self.reponse, self.erreur = reponse, erreur

    def stream(self, *a, **kw):
        if self.erreur:
            raise self.erreur
        return self.reponse


def test_lire():
    page = p.lire(_Client(_Reponse(200, "text/html; charset=utf-8", ARTICLE.encode())), "https://exemple.fr/x")
    assert page["lien"] == "https://exemple.fr/final" and "Salle Exemple" in page["texte"]
    assert p.lire(_Client(_Reponse(403, "text/html", b"")), "u") is None
    assert p.lire(_Client(_Reponse(200, "application/pdf", b"%PDF")), "u") is None
    assert p.lire(_Client(_Reponse(200, "text/html", b"x" * (p.TAILLE_MAX + 1))), "u") is None
    assert p.lire(_Client(erreur=TimeoutError()), "u") is None
