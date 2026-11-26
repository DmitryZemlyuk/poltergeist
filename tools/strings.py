#!/usr/bin/env python3
"""Source of truth for UI strings (en, ru, uk). Generates Resources/<lang>.lproj/Localizable.strings.
Format specifiers: %@ for text, %ld for numbers. Use the short dash (–) in UI text, never the long one."""
import os

S = {
# General
"menu.clean": ("Clean", "Очистка", "Очищення"),
"cancel": ("Cancel", "Отмена", "Скасувати"),
"done": ("Done", "Готово", "Готово"),
"search.prompt": ("Search", "Поиск", "Пошук"),
"scan.progress": ("Looking for junk…", "Ищу мусор…", "Шукаю сміття…"),
"action.rescan": ("Scan again", "Сканировать заново", "Сканувати знову"),
"action.scanall": ("Scan everything", "Сканировать всё", "Сканувати все"),
"action.clean": ("Clean", "Очистить", "Очистити"),
"action.clean.size": ("Clean %@", "Очистить %@", "Очистити %@"),
"action.reveal": ("Show in Finder", "Показать в Finder", "Показати у Finder"),
"action.totrash": ("Move to Trash", "В Корзину", "У Кошик"),
"action.totrash.size": ("Move %@ to Trash", "В Корзину %@", "У Кошик %@"),
"sidebar.cleanup": ("Cleanup", "Очистка", "Очищення"),
"sidebar.analysis": ("Analysis", "Анализ", "Аналіз"),
"disk.free": ("%@ free of %@", "Свободно %@ из %@", "Вільно %@ з %@"),
"ring.free": ("free", "свободно", "вільно"),

# Sections
"section.overview": ("Overview", "Обзор", "Огляд"),
"section.caches": ("Caches and logs", "Кэши и логи", "Кеші та логи"),
"section.developer": ("Development", "Разработка", "Розробка"),
"section.trash": ("Trash and Downloads", "Корзина и загрузки", "Кошик і завантаження"),
"section.backups": ("Backups and Mail", "Бэкапы и Почта", "Бекапи та Пошта"),
"section.map": ("Disk map", "Карта диска", "Карта диска"),
"section.large": ("Large files", "Большие файлы", "Великі файли"),
"section.apps": ("Apps", "Приложения", "Застосунки"),
"section.leftovers": ("Leftovers", "Остатки удалённых", "Залишки видалених"),

# Lists
"list.subtitle": ("Found %@ · selected %@", "Найдено %@ · выбрано %@", "Знайдено %@ · вибрано %@"),
"empty.title": ("All clean", "Чисто", "Чисто"),
"empty.text": ("Nothing to clean here right now.", "Здесь пока нечего чистить.", "Тут поки нічого чистити."),
"overview.found": ("%@ of junk found", "Найдено мусора: %@", "Знайдено сміття: %@"),
"overview.selected": ("Selected for cleaning: %@", "Выбрано для очистки: %@", "Вибрано для очищення: %@"),
"overview.sections": ("Where it is", "Где он лежит", "Де воно лежить"),
"overview.row.selected": ("selected %@", "выбрано %@", "вибрано %@"),

# Confirmation and report
"confirm.title": ("Clean the selected items?", "Очистить выбранное?", "Очистити вибране?"),
"confirm.go": ("Clean", "Очистить", "Очистити"),
"confirm.count": ("Items: %ld", "Объектов: %ld", "Об'єктів: %ld"),
"confirm.now": ("Deleted right away (they come back on their own): %@", "Удалится сразу (это восстановится само): %@", "Видалиться одразу (це відновиться саме): %@"),
"confirm.trash": ("Moved to the Trash: %@", "Переместится в Корзину: %@", "Переміститься в Кошик: %@"),
"report.title": ("Done", "Готово", "Готово"),
"report.title.partial": ("Done, with a few skips", "Готово, но не всё", "Готово, але не все"),
"report.freed": ("Freed %@", "Освобождено %@", "Звільнено %@"),
"report.trashed": ("Moved to the Trash: %@ – it is freed when you empty the Trash", "В Корзине: %@ – место освободится, когда очистите Корзину", "У Кошику: %@ – місце звільниться, коли очистите Кошик"),
"report.nothing": ("There was nothing left to delete.", "Удалять было уже нечего.", "Видаляти вже не було чого."),
"report.failed": ("Couldn't delete: %ld", "Не удалось удалить: %ld", "Не вдалося видалити: %ld"),
"fail.noaccess": ("No access. Give Poltergeist Full Disk Access.", "Нет доступа. Дайте Poltergeist полный доступ к диску.", "Немає доступу. Надайте Poltergeist повний доступ до диска."),
"fail.protected": ("Protected location – skipped.", "Защищённое место – пропущено.", "Захищене місце – пропущено."),

# Full Disk Access
"fda.open": ("Open Settings", "Открыть настройки", "Відкрити параметри"),
"fda.banner.title": ("Part of the junk is hidden", "Часть мусора не видна", "Частину сміття не видно"),
"fda.banner.text": ("Allow Full Disk Access to see the Trash, Mail, device backups and App Store apps' caches.", "Дайте полный доступ к диску, чтобы видеть Корзину, Почту, бэкапы устройств и кэши приложений из App Store.", "Надайте повний доступ до диска, щоб бачити Кошик, Пошту, бекапи пристроїв і кеші застосунків з App Store."),
"fda.on": ("Full Disk Access is on", "Полный доступ к диску включён", "Повний доступ до диска ввімкнено"),
"fda.off": ("No Full Disk Access", "Нет полного доступа к диску", "Немає повного доступу до диска"),
"fda.explain": ("System Settings → Privacy & Security → Full Disk Access → turn on Poltergeist. After each update of the app macOS may ask again.", "System Settings → Privacy & Security → Full Disk Access → включите Poltergeist. После каждого обновления приложения macOS может попросить снова.", "System Settings → Privacy & Security → Full Disk Access → увімкніть Poltergeist. Після кожного оновлення застосунку macOS може попросити знову."),

# Item rows (from the scanners)
"item.count": ("%@ items", "Объектов: %@", "Об'єктів: %@"),
"item.running": ("The app is running – left out", "Приложение запущено – не трогаю", "Застосунок запущено – не чіпаю"),
"item.system": ("System cache – only if you're sure", "Системный кэш – только если уверены", "Системний кеш – лише якщо впевнені"),
"item.newest": ("Newest – kept by default", "Самая новая – оставлена", "Найновіша – залишена"),
"group.caches": ("Caches", "Кэши", "Кеші"),
"group.logs": ("Logs and traces", "Логи и следы", "Логи та сліди"),
"item.caches.apps": ("App caches", "Кэши приложений", "Кеші застосунків"),
"item.caches.sandboxed": ("App Store app caches", "Кэши приложений из App Store", "Кеші застосунків з App Store"),
"item.logs.apps": ("App logs", "Логи приложений", "Логи застосунків"),
"item.logs.crash": ("Crash reports", "Отчёты о сбоях", "Звіти про збої"),
"item.savedstate": ("Saved window state", "Сохранённое состояние окон", "Збережений стан вікон"),
"item.savedstate.sub": ("Apps will open without their last windows", "Приложения откроются без прошлых окон", "Застосунки відкриються без попередніх вікон"),
"group.node": ("Node and packages", "Node и пакеты", "Node і пакети"),
"group.android": ("Android and Java", "Android и Java", "Android і Java"),
"group.projects": ("Old projects", "Старые проекты", "Старі проєкти"),
"item.simulators": ("Unused simulators", "Неиспользуемые симуляторы", "Невикористовувані симулятори"),
"item.simcaches": ("Simulator caches", "Кэши симуляторов", "Кеші симуляторів"),
"item.devicesupport.sub": ("Debug symbols of old OS versions", "Символы отладки старых версий систем", "Символи налагодження старих версій систем"),
"item.archives.sub": ("App Store builds – check before deleting", "Сборки для App Store – проверь перед удалением", "Збірки для App Store – перевір перед видаленням"),
"item.xcodecache": ("Xcode cache", "Кэш Xcode", "Кеш Xcode"),
"item.previews": ("SwiftUI previews", "Превью SwiftUI", "Прев'ю SwiftUI"),
"item.swiftpm": ("Swift packages cache", "Кэш пакетов Swift", "Кеш пакетів Swift"),
"item.cocoapods": ("CocoaPods cache", "Кэш CocoaPods", "Кеш CocoaPods"),
"item.npm": ("npm cache", "Кэш npm", "Кеш npm"),
"item.npx": ("npx downloads", "Загрузки npx", "Завантаження npx"),
"item.yarn": ("Yarn cache", "Кэш Yarn", "Кеш Yarn"),
"item.pnpm": ("pnpm store", "Хранилище pnpm", "Сховище pnpm"),
"item.nodegyp": ("node-gyp headers", "Заголовки node-gyp", "Заголовки node-gyp"),
"item.nvmcache": ("nvm downloads", "Загрузки nvm", "Завантаження nvm"),
"item.nvm": ("Old Node versions", "Старые версии Node", "Старі версії Node"),
"item.nvm.sub": ("Kept: %@", "Остаются: %@", "Залишаються: %@"),
"item.brew": ("Homebrew cache", "Кэш Homebrew", "Кеш Homebrew"),
"item.pip": ("pip cache", "Кэш pip", "Кеш pip"),
"item.playwright": ("Playwright browsers", "Браузеры Playwright", "Браузери Playwright"),
"item.gradle": ("Gradle cache", "Кэш Gradle", "Кеш Gradle"),
"item.gradledaemon": ("Gradle daemon logs", "Логи демона Gradle", "Логи демона Gradle"),
"item.gradlewrapper": ("Gradle versions", "Версии Gradle", "Версії Gradle"),
"item.androidcache": ("Android cache", "Кэш Android", "Кеш Android"),
"item.avd": ("Android emulators", "Эмуляторы Android", "Емулятори Android"),
"item.maven": ("Maven repository", "Репозиторий Maven", "Репозиторій Maven"),
"item.nodemodules": ("node_modules in old projects", "node_modules в старых проектах", "node_modules у старих проєктах"),
"item.nodemodules.sub": ("Projects: %@, untouched for %@+ days", "Проектов: %@, не открывались %@+ дн.", "Проєктів: %@, не відкривались %@+ дн."),
"sub.project": ("%@ · untouched for %@ days", "%@ · не открывался %@ дн.", "%@ · не відкривався %@ дн."),
"group.trash": ("Trash", "Корзина", "Кошик"),
"group.downloads": ("Downloads", "Загрузки", "Завантаження"),
"item.trash": ("Trash", "Корзина", "Кошик"),
"item.trash.sub": ("Items: %@ – deleted for good", "Объектов: %@ – удалятся навсегда", "Об'єктів: %@ – видаляться назавжди"),
"item.installers": ("Installers (.dmg, .pkg)", "Установщики (.dmg, .pkg)", "Інсталятори (.dmg, .pkg)"),
"item.olddownloads": ("Downloaded over %@ days ago", "Загружено больше %@ дн. назад", "Завантажено понад %@ дн. тому"),
"sub.daysago": ("Downloaded %@ days ago", "Загружено %@ дн. назад", "Завантажено %@ дн. тому"),
"sub.needsaccess": ("Needs Full Disk Access", "Нужен полный доступ к диску", "Потрібен повний доступ до диска"),
"group.devices": ("iPhone and iPad", "iPhone и iPad", "iPhone та iPad"),
"group.mail": ("Mail", "Почта", "Пошта"),
"item.iosbackups": ("Device backups", "Бэкапы устройств", "Бекапи пристроїв"),
"sub.backupdate": ("Last backup %@ days ago", "Последний бэкап %@ дн. назад", "Останній бекап %@ дн. тому"),
"item.ipsw": ("Software updates (.ipsw)", "Прошивки (.ipsw)", "Прошивки (.ipsw)"),
"item.maildownloads": ("Opened attachments", "Открытые вложения", "Відкриті вкладення"),
"item.maildownloads.sub": ("Copies – the letters keep theirs", "Копии – в письмах они остаются", "Копії – у листах вони залишаються"),
"group.leftovers": ("Apps that are gone", "Удалённые приложения", "Видалені застосунки"),
"sub.leftover": ("%@ · %@", "%@ · %@", "%@ · %@"),

# Disk map and large files
"map.empty.title": ("See what takes the space", "Посмотрите, что занимает место", "Подивіться, що займає місце"),
"map.empty.text": ("Poltergeist measures every folder and draws them as blocks. Click a block to see it, double-click to go inside.", "Poltergeist измерит каждую папку и нарисует их блоками. Клик – выбрать блок, двойной клик – зайти внутрь.", "Poltergeist виміряє кожну теку й намалює їх блоками. Клік – вибрати блок, подвійний клік – зайти всередину."),
"map.scan.home": ("Scan home folder", "Сканировать домашнюю папку", "Сканувати домашню теку"),
"map.choose": ("Choose folder…", "Выбрать папку…", "Вибрати теку…"),
"map.choose.prompt": ("Scan", "Сканировать", "Сканувати"),
"map.scanning": ("Measuring… %ld files", "Измеряю… файлов: %ld", "Вимірюю… файлів: %ld"),
"map.up": ("Up one level", "На уровень выше", "На рівень вище"),
"map.other": ("Smaller files", "Мелкие файлы", "Дрібні файли"),
"map.inside": ("Inside", "Внутри", "Всередині"),
"map.open": ("Open", "Открыть", "Відкрити"),
"stat.size": ("size", "размер", "розмір"),
"stat.files": ("files", "файлов", "файлів"),
"stat.modified": ("changed", "изменено", "змінено"),
"trash.confirm.title": ("Move to the Trash?", "Переместить в Корзину?", "Перемістити в Кошик?"),
"trash.confirm.text": ("“%@” (%@) goes to the Trash. You can put it back from there.", "«%@» (%@) переместится в Корзину. Оттуда её можно вернуть.", "«%@» (%@) переміститься в Кошик. Звідти її можна повернути."),
"trash.confirm.many": ("Files: %ld, %@. You can put them back from the Trash.", "Файлов: %ld, %@. Их можно вернуть из Корзины.", "Файлів: %ld, %@. Їх можна повернути з Кошика."),
"large.threshold": ("Bigger than", "Больше чем", "Більші за"),
"large.header": ("Files: %ld, bigger than %@", "Файлов: %ld, больше %@", "Файлів: %ld, більших за %@"),
"large.empty": ("No large files", "Больших файлов нет", "Великих файлів немає"),
"large.empty.text": ("Nothing bigger than %@ here.", "Здесь нет ничего больше %@.", "Тут немає нічого більшого за %@."),
"large.need.title": ("Find large files", "Найти большие файлы", "Знайти великі файли"),
"large.need.text": ("They are found together with the disk map – one scan for both.", "Они ищутся вместе с картой диска – одно сканирование на оба раздела.", "Вони шукаються разом з картою диска – одне сканування на обидва розділи."),

# Apps
"apps.header": ("Apps: %ld", "Приложений: %ld", "Застосунків: %ld"),
"apps.subtitle": ("Together %@", "Вместе %@", "Разом %@"),
"apps.sort": ("Sort", "Сортировка", "Сортування"),
"apps.sort.size": ("By size", "По размеру", "За розміром"),
"apps.sort.name": ("By name", "По имени", "За назвою"),
"apps.sort.lastUsed": ("Unused first", "Сначала давно не открытые", "Спершу давно не відкриті"),
"apps.lastused": ("opened %@", "открывалось %@", "відкривався %@"),
"apps.lastused.unknown": ("never opened", "не открывалось", "не відкривався"),
"apps.uninstall": ("Uninstall…", "Удалить…", "Видалити…"),
"uninstall.title": ("Uninstall %@", "Удалить %@", "Видалити %@"),
"uninstall.running": ("The app is open – it will be quit first.", "Приложение открыто – сначала оно закроется.", "Застосунок відкрито – спершу він закриється."),
"uninstall.searching": ("Looking for its files…", "Ищу его файлы…", "Шукаю його файли…"),
"uninstall.related": ("Its files outside the app", "Его файлы вне приложения", "Його файли поза застосунком"),
"uninstall.norelated": ("No other files found – only the app itself goes.", "Других файлов нет – удалится только само приложение.", "Інших файлів немає – видалиться лише сам застосунок."),
"uninstall.fda": ("With Full Disk Access more of its files can be found.", "С полным доступом к диску найдётся больше его файлов.", "З повним доступом до диска знайдеться більше його файлів."),
"uninstall.total": ("Together %@ – everything goes to the Trash", "Всего %@ – всё уйдёт в Корзину", "Разом %@ – усе піде в Кошик"),
"uninstall.go": ("Uninstall", "Удалить", "Видалити"),

# Settings
"settings.language": ("Language", "Язык интерфейса", "Мова інтерфейсу"),
"settings.language.system": ("Same as system", "Как в системе", "Як у системі"),
"settings.language.restart": ("The new language applies after a restart", "Новый язык применится после перезапуска", "Нова мова застосується після перезапуску"),
"settings.restart": ("Restart", "Перезапустить", "Перезапустити"),
"settings.search": ("What counts as old", "Что считать старым", "Що вважати старим"),
"settings.downloads": ("Downloads", "Загрузки", "Завантаження"),
"settings.projects": ("Projects with node_modules", "Проекты с node_modules", "Проєкти з node_modules"),
"settings.days": ("%ld days", "%ld дн.", "%ld дн."),
"settings.access": ("Access", "Доступ", "Доступ"),
}

def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

if __name__ == "__main__":
    for k, v in S.items():
        assert len(v) == 3, k
        for s in v:
            assert "—" not in s, f"long dash in {k}"
        specs = [sorted(__import__("re").findall(r"%(?:ld|@)", s)) for s in v]
        assert specs[0] == specs[1] == specs[2], f"format mismatch in {k}"
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources")
    for i, lang in enumerate(["en", "ru", "uk"]):
        d = os.path.join(root, f"{lang}.lproj")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "Localizable.strings"), "w", encoding="utf-8") as f:
            f.write("/* Generated by tools/strings.py – edit there. */\n\n")
            for k in sorted(S):
                f.write(f'"{k}" = "{esc(S[k][i])}";\n')
    print(len(S), "keys")
