"""Page d'un lien partagé, lue par la vigie avant le tri (11/11/2026).

Le tri n'a pas d'outil : sans cette lecture, il ne voyait que le résumé joint au partage (« le village de Noël
japonais est de retour à Paris en décembre ») et ni la date, ni le lieu, ni le nom de l'événement, écrits dans la
page. La vigie lit donc la page d'une tâche PARTAGÉE (ligne « 📩 Message partagé ») qui a un lien et pas encore de
lieu, et en passe au modèle un extrait court : titre, description, événements décrits par la page (JSON-LD
`Event`) et texte de l'article. Fonctions pures, sauf `lire` (réseau)."""

from html import unescape
from html.parser import HTMLParser
import json
import re

LIGNE_PARTAGE = "📩 Message partagé"
# Liens déjà traités ailleurs (lieu lu dans le lien par l'app, œuvres cherchées par la vigie, mails, documents) ou
# qui ne donnent rien sans compte : pas de lecture.
HOTES_IGNORES = ("maps.apple.com", "maps.google.", "google.com/maps", "goo.gl/maps", "maps.app.goo.gl",
                 "mail.google.com", "docs.google.com", "drive.google.com", "youtube.com", "youtu.be",
                 "open.spotify.com", "spotify.link", "music.apple.com", "deezer.com", "netflix.com", "disneyplus.com",
                 "tv.apple.com", "canalplus.com", "primevideo.com", "instagram.com", "facebook.com", "tiktok.com",
                 "x.com", "twitter.com", "doctolib.fr")
TEXTE_MAX = 6000
TAILLE_MAX = 3_000_000
DELAI = 8.0
AGENT = ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) "
         "Version/18.0 Mobile/15E148 Safari/604.1")

_LIEN = re.compile(r"https?://[^\s<>\"']+")


def lien_a_lire(valeur):
    """Premier lien d'une tâche partagée à lire, ou None (tâche non partagée, déjà avec un lieu, faite, ou lien
    traité ailleurs)."""
    notes = valeur.get("notes") or ""
    if valeur.get("fait") or valeur.get("lieu") or LIGNE_PARTAGE not in notes:
        return None
    for lien in _LIEN.findall(notes):
        lien = lien.rstrip(".,;:!?)»")
        if not any(h in lien.lower() for h in HOTES_IGNORES):
            return lien
    return None


class _Lecteur(HTMLParser):
    """Titre, balises meta, blocs JSON-LD et texte visible (celui de <article> ou <main> à part)."""

    SAUTES = {"script", "style", "noscript", "svg", "nav", "header", "footer", "aside", "form", "iframe", "template",
              "button", "select"}
    BLOCS = {"p", "br", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6", "tr", "section", "article", "ul", "ol",
             "blockquote", "figcaption", "dd", "dt"}
    VIDES = {"br", "img", "meta", "link", "input", "hr", "source", "wbr", "area", "base", "col", "embed", "param",
             "track"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.titre, self.meta, self.jsonld = "", {}, []
        self.texte, self.texte_article = [], []
        self._pile = []  # balises ouvertes (hors vides)
        self._saute = 0
        self._article = 0
        self._dans_titre = False
        self._jsonld = None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "meta":
            cle = (a.get("property") or a.get("name") or "").lower()
            if cle and a.get("content") and cle not in self.meta:
                self.meta[cle] = a["content"]
            return
        if tag in self.VIDES:
            if tag == "br":
                self._coupe()
            return
        self._pile.append(tag)
        if tag == "script" and (a.get("type") or "").lower() == "application/ld+json":
            self._jsonld = []
        if tag in self.SAUTES:
            self._saute += 1
        if tag in ("article", "main"):
            self._article += 1
        if tag == "title":
            self._dans_titre = True
        if tag in self.BLOCS:
            self._coupe()

    def handle_endtag(self, tag):
        if tag in self.VIDES or tag not in self._pile:
            return
        while self._pile:
            ouvert = self._pile.pop()
            if ouvert == "script" and self._jsonld is not None:
                self.jsonld.append("".join(self._jsonld))
                self._jsonld = None
            if ouvert in self.SAUTES:
                self._saute -= 1
            if ouvert in ("article", "main"):
                self._article -= 1
            if ouvert == "title":
                self._dans_titre = False
            if ouvert in self.BLOCS:
                self._coupe()
            if ouvert == tag:
                break

    def handle_data(self, data):
        if self._jsonld is not None:
            self._jsonld.append(data)
            return
        if self._dans_titre:
            self.titre += data
            return
        if self._saute:
            return
        self.texte.append(data)
        if self._article:
            self.texte_article.append(data)

    def _coupe(self):
        self.texte.append("\n")
        if self._article:
            self.texte_article.append("\n")


def _propre(morceaux):
    lignes = (re.sub(r"\s+", " ", ligne).strip() for ligne in "".join(morceaux).split("\n"))
    return "\n".join(ligne for ligne in lignes if ligne)


def _objets(donnee):
    """Tous les objets d'un bloc JSON-LD (listes et @graph compris)."""
    if isinstance(donnee, list):
        for d in donnee:
            yield from _objets(d)
    elif isinstance(donnee, dict):
        yield donnee
        for d in donnee.get("@graph") or []:
            yield from _objets(d)


def _type(objet):
    t = objet.get("@type")
    return " ".join(t) if isinstance(t, list) else str(t or "")


def _adresse(adresse):
    if isinstance(adresse, str):
        return adresse.strip()
    if not isinstance(adresse, dict):
        return ""
    rue, cp, ville = (str(adresse.get(k) or "").strip() for k in ("streetAddress", "postalCode", "addressLocality"))
    return ", ".join(x for x in (rue, " ".join(y for y in (cp, ville) if y)) if x)


def evenements(blocs):
    """Événements décrits par la page (JSON-LD de type …Event) : nom, début, fin, lieu, adresse."""
    out = []
    for bloc in blocs:
        try:
            donnee = json.loads(bloc)
        except ValueError:
            continue
        for o in _objets(donnee):
            if "Event" not in _type(o):
                continue
            lieu = o.get("location")
            lieu = lieu[0] if isinstance(lieu, list) and lieu else lieu
            ev = {"nom": unescape(str(o.get("name") or "")).strip(), "debut": str(o.get("startDate") or ""),
                  "fin": str(o.get("endDate") or "")}
            if isinstance(lieu, dict):
                ev["lieu"] = unescape(str(lieu.get("name") or "")).strip()
                ev["adresse"] = _adresse(lieu.get("address"))
            elif isinstance(lieu, str):
                ev["lieu"] = lieu.strip()
            out.append({k: v for k, v in ev.items() if v})
            if len(out) >= 5:
                return out
    return out


def extraire(html, url=""):
    """Ce que le tri voit de la page : {lien, titre, description, evenements, texte} (champs vides omis).

    Le texte est celui de l'article (<article>, sinon <main>, sinon toute la page visible) ; trop long, on garde
    le début et la fin, où se trouvent d'habitude les infos pratiques (dates, adresse, prix)."""
    lecteur = _Lecteur()
    try:
        lecteur.feed(html)
        lecteur.close()
    except Exception:  # noqa: BLE001 — page mal formée : on garde ce qui a été lu
        pass
    texte = _propre(lecteur.texte_article) or _propre(lecteur.texte)
    if len(texte) > TEXTE_MAX:
        moitie = TEXTE_MAX // 2
        texte = texte[:moitie] + "\n[…]\n" + texte[-moitie:]
    m = lecteur.meta
    page = {
        "lien": url,
        "titre": (m.get("og:title") or lecteur.titre or "").strip(),
        "description": (m.get("og:description") or m.get("description") or "").strip(),
        "evenements": evenements(lecteur.jsonld),
        "texte": texte,
    }
    return {k: v for k, v in page.items() if v}


def lire(client, url):
    """Page lue (dict d'`extraire`), ou None (erreur, page trop lourde, pas du HTML). `client` : httpx.Client."""
    try:
        with client.stream("GET", url, timeout=DELAI, follow_redirects=True,
                           headers={"User-Agent": AGENT, "Accept-Language": "fr-FR,fr;q=0.9"}) as r:
            if r.status_code != 200 or "html" not in r.headers.get("content-type", "html"):
                return None
            corps = b""
            for morceau in r.iter_bytes():
                corps += morceau
                if len(corps) > TAILLE_MAX:
                    return None
            return extraire(corps.decode(r.encoding or "utf-8", errors="replace"), str(r.url))
    except Exception:  # noqa: BLE001 — réseau, délai, encodage : le tri se fait sans la page
        return None
