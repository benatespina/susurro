"""
Curated dictionary of common English anglicisms with hand-crafted IPA
pronunciations targeted at a Spanish-speaking voice (Azure es-ES).

Keep entries lowercase. Lookup is case-insensitive.
"""

ES_DICT: dict[str, dict[str, str]] = {
    "api": {"ipa": "ˈapi"},
    "framework": {"ipa": "ˈfɾejmwoɾk"},
    "frameworks": {"ipa": "ˈfɾejmwoɾks"},
    "deploy": {"ipa": "deˈplɔj"},
    "deployment": {"ipa": "deˈplojment"},
    "deployments": {"ipa": "deˈplojments"},
    "feedback": {"ipa": "ˈfidbak"},
    "backend": {"ipa": "bakˈend"},
    "frontend": {"ipa": "fɾonˈtend"},
    "endpoint": {"ipa": "ˈendpojnt"},
    "endpoints": {"ipa": "ˈendpojnts"},
    "stack": {"ipa": "estak"},
    "queue": {"ipa": "kju"},
    "cache": {"ipa": "kaʃ"},
    "branch": {"ipa": "bɾantʃ"},
    "merge": {"ipa": "merʃ"},
    "commit": {"ipa": "koˈmit"},
    "commits": {"ipa": "koˈmits"},
    "release": {"ipa": "ɾiˈlis"},
    "releases": {"ipa": "ɾiˈlises"},
    "feature": {"ipa": "ˈfitʃeɾ"},
    "features": {"ipa": "ˈfitʃeɾs"},
    "build": {"ipa": "bild"},
    "builds": {"ipa": "bilds"},
    "router": {"ipa": "ˈɾuteɾ"},
    "buffer": {"ipa": "ˈbafeɾ"},
    "log": {"ipa": "loɡ"},
    "logs": {"ipa": "loɡs"},
    "thread": {"ipa": "tɾed"},
    "threads": {"ipa": "tɾeds"},
    "string": {"ipa": "estɾiŋ"},
    "strings": {"ipa": "estɾiŋs"},
    "scope": {"ipa": "eskop"},
    "container": {"ipa": "konˈtejneɾ"},
    "containers": {"ipa": "konˈtejneɾs"},
    "developer": {"ipa": "deˈbeloper"},
    "developers": {"ipa": "deˈbelopers"},
    "testing": {"ipa": "ˈtestin"},
    "wrapper": {"ipa": "ˈɾapeɾ"},
    "engine": {"ipa": "ˈenʃin"},
    "request": {"ipa": "ɾiˈkwest"},
    "requests": {"ipa": "ɾiˈkwests"},
    "patch": {"ipa": "patʃ"},
    "linter": {"ipa": "ˈlinteɾ"},
    "lint": {"ipa": "lint"},
    "review": {"ipa": "ɾiˈbju"},
    "reviews": {"ipa": "ɾiˈbjus"},
    "pull": {"ipa": "pul"},
    "push": {"ipa": "puʃ"},
    "issue": {"ipa": "ˈiʃu"},
    "issues": {"ipa": "ˈiʃus"},
    "tag": {"ipa": "taɡ"},
    "tags": {"ipa": "taɡs"},
    "lookup": {"ipa": "ˈlukap"},
    "fallback": {"ipa": "ˈfolbak"},
    "rollback": {"ipa": "ˈɾolbak"},
    "deploy": {"ipa": "deˈploj"},
    "callback": {"ipa": "ˈkolbak"},
    "callbacks": {"ipa": "ˈkolbaks"},
    "workflow": {"ipa": "ˈweɾkflow"},
    "workflows": {"ipa": "ˈweɾkflows"},
    "pipeline": {"ipa": "ˈpajplajn"},
    "pipelines": {"ipa": "ˈpajplajns"},
    "dashboard": {"ipa": "ˈdaʃboɾd"},
    "dashboards": {"ipa": "ˈdaʃboɾds"},
    "frontends": {"ipa": "fɾonˈtends"},
    "backends": {"ipa": "bakˈends"},
    "scrum": {"ipa": "eskɾum"},
    "sprint": {"ipa": "espɾint"},
    "sprints": {"ipa": "espɾints"},
    "stand-up": {"ipa": "ˈstandap"},
    "standup": {"ipa": "ˈstandap"},
    "kickoff": {"ipa": "ˈkikof"},
    "release": {"ipa": "ɾiˈlis"},
    "rollout": {"ipa": "ɾoˈlawt"},
    "kanban": {"ipa": "ˈkanban"},
    "lookiero": {"ipa": "luˈkjeɾo"},
}


ACRONYMS: set[str] = {
    "API", "URL", "URI", "HTTP", "HTTPS", "JSON", "XML", "CSS", "HTML", "SQL",
    "REST", "JWT", "UUID", "CORS", "DNS", "SSH", "TCP", "UDP", "RAM", "ROM",
    "CPU", "GPU", "SSD", "HDD", "USB", "PDF", "PNG", "JPG", "SVG", "GIF",
    "AWS", "GCP", "IDE", "MVP", "QA", "UI", "UX", "OS", "IO", "DB",
    "CI", "CD", "TLS", "SSL", "FTP", "VPN", "LAN", "WAN", "VPC", "IAM",
    "S3", "EC2", "EKS", "RDS", "SDK", "ORM", "SPA", "SSR", "CSR", "SSG",
    "PR", "MR", "WIP", "ETA", "TBD", "FYI", "PoC", "POC", "B2B", "B2C",
}


def lookup(word: str, language: str) -> dict | None:
    if language != "es":
        return None
    return ES_DICT.get(word.lower())


def is_acronym(word: str) -> bool:
    if word in ACRONYMS:
        return True
    if len(word) < 2 or len(word) > 6:
        return False
    return word.isupper() and word.isalpha()
