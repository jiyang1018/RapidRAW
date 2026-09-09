import json
from pathlib import Path

LOCALES_DIR = Path("./locales")

TRANSLATIONS = {
    "ca": {
        "library": {
            "folders": {
                "addFolder": "Afegeix una carpeta",
                "tooltips": {
                    "moreOptions": "Opcions",
                    "navBack": "Enrere",
                    "navForward": "Endavant"
                }
            }
        }
    },
    "de": {
        "library": {
            "folders": {
                "addFolder": "Ordner hinzufügen",
                "tooltips": {
                    "moreOptions": "Optionen",
                    "navBack": "Zurück",
                    "navForward": "Vorwärts"
                }
            }
        }
    },
    "en": {
        "library": {
            "folders": {
                "addFolder": "Add folder",
                "tooltips": {
                    "moreOptions": "Options",
                    "navBack": "Go Back",
                    "navForward": "Go Forward"
                }
            }
        }
    },
    "es": {
        "library": {
            "folders": {
                "addFolder": "Añadir carpeta",
                "tooltips": {
                    "moreOptions": "Opciones",
                    "navBack": "Atrás",
                    "navForward": "Adelante"
                }
            }
        }
    },
    "fr": {
        "library": {
            "folders": {
                "addFolder": "Ajouter un dossier",
                "tooltips": {
                    "moreOptions": "Options",
                    "navBack": "Retour",
                    "navForward": "Suivant"
                }
            }
        }
    },
    "it": {
        "library": {
            "folders": {
                "addFolder": "Aggiungi cartella",
                "tooltips": {
                    "moreOptions": "Opzioni",
                    "navBack": "Indietro",
                    "navForward": "Avanti"
                }
            }
        }
    },
    "ja": {
        "library": {
            "folders": {
                "addFolder": "フォルダーを追加",
                "tooltips": {
                    "moreOptions": "オプション",
                    "navBack": "戻る",
                    "navForward": "進む"
                }
            }
        }
    },
    "ko": {
        "library": {
            "folders": {
                "addFolder": "폴더 추가",
                "tooltips": {
                    "moreOptions": "옵션",
                    "navBack": "뒤로",
                    "navForward": "앞으로"
                }
            }
        }
    },
    "pl": {
        "library": {
            "folders": {
                "addFolder": "Dodaj folder",
                "tooltips": {
                    "moreOptions": "Opcje",
                    "navBack": "Wstecz",
                    "navForward": "Dalej"
                }
            }
        }
    },
    "pt": {
        "library": {
            "folders": {
                "addFolder": "Adicionar pasta",
                "tooltips": {
                    "moreOptions": "Opções",
                    "navBack": "Voltar",
                    "navForward": "Avançar"
                }
            }
        }
    },
    "ru": {
        "library": {
            "folders": {
                "addFolder": "Добавить папку",
                "tooltips": {
                    "moreOptions": "Опции",
                    "navBack": "Назад",
                    "navForward": "Вперед"
                }
            }
        }
    },
    "zh-CN": {
        "library": {
            "folders": {
                "addFolder": "添加文件夹",
                "tooltips": {
                    "moreOptions": "选项",
                    "navBack": "后退",
                    "navForward": "前进"
                }
            }
        }
    },
    "zh-TW": {
        "library": {
            "folders": {
                "addFolder": "新增資料夾",
                "tooltips": {
                    "moreOptions": "選項",
                    "navBack": "後退",
                    "navForward": "前進"
                }
            }
        }
    }
}

def deep_merge(target: dict, source: dict):
    """Recursively merges source dict into target dict."""
    for key, value in source.items():
        if isinstance(value, dict):
            node = target.setdefault(key, {})
            if isinstance(node, dict):
                deep_merge(node, value)
        else:
            target[key] = value

def sort_dict_recursively(item):
    if isinstance(item, dict):
        return {k: sort_dict_recursively(v) for k, v in sorted(item.items())}
    elif isinstance(item, list):
        return [sort_dict_recursively(x) for x in item]
    return item

def update_json_file(file_path: Path, trans: dict):
    if not file_path.exists():
        print(f"Skipping: {file_path.name} (File not found)")
        return

    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        print(f"Error parsing JSON in {file_path.name}. Skipping.")
        return

    # 1. Merge new translations
    deep_merge(data, trans)

    # 2. Sort alphabetically to maintain formatting consistency
    sorted_data = sort_dict_recursively(data)

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(sorted_data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"Updated and Sorted: {file_path.name}")

def main():
    if not LOCALES_DIR.exists():
        print(f"Error: Locales directory '{LOCALES_DIR}' does not exist.")
        return

    print("Starting translation updates for folder navigation tooltips...")
    for lang, trans in TRANSLATIONS.items():
        file_path = LOCALES_DIR / f"{lang}.json"
        update_json_file(file_path, trans)
    print("Done!")

if __name__ == "__main__":
    main()
