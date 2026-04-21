import from .ui.button { Button }

def:pub Navbar() -> JsxElement {
    has scrolled: bool = False;
    has mobile_open: bool = False;

    can with entry {
        def handle_scroll() -> None {
            scrolled = globalThis.window.scrollY > 20;
        }
        globalThis.window.addEventListener("scroll", handle_scroll);
    }

    def scroll_to(id: str) -> None {
        el = globalThis.document.getElementById(id);
        if el { el.scrollIntoView({"behavior": "smooth"}); }
        mobile_open = False;
    }

    def nav_features() -> None { scroll_to("features"); }
    def nav_getting_started() -> None { scroll_to("getting-started"); }
    def toggle_mobile() -> None { mobile_open = not mobile_open; }

    def handle_marketplace() -> None {
        globalThis.open("https://marketplace.visualstudio.com/items?itemName=jaseci-labs.jaccoder", "_blank");
    }

    def handle_github() -> None {
        globalThis.open("https://github.com/Jaseci-Labs/jaseci", "_blank");
    }

    navbar_class = "fixed top-0 left-0 right-0 z-50 transition-all duration-300 " + (
        "navbar-blur bg-[#050507]/80 border-b border-white/[0.05]" if scrolled else "bg-transparent border-b border-transparent"
    );

    return (
        <nav className={navbar_class}>
            <div className="max-w-6xl mx-auto px-6 h-16 flex items-center justify-between">
                <div className="flex items-center gap-2.5">
                    <img src="/static/assets/jaseci_logo.png" alt="JacCoder" className="w-7 h-7" />
                    <span className="text-base font-bold gradient-text">JacCoder</span>
                </div>

                <div className="hidden md:flex items-center gap-0.5">
                    <button onClick={nav_features} className="px-3.5 py-2 text-[0.8125rem] text-white/40 hover:text-white/80 transition-colors rounded-lg">Features</button>
                    <button onClick={nav_getting_started} className="px-3.5 py-2 text-[0.8125rem] text-white/40 hover:text-white/80 transition-colors rounded-lg">Get Started</button>
                </div>

                <div className="hidden md:flex items-center">
                    <Button size="sm" onClick={handle_marketplace} className="h-8 px-4 rounded-lg text-xs font-semibold gap-1.5">
                        Install
                    </Button>
                </div>

                <button onClick={toggle_mobile} className="md:hidden p-2 text-white/40 hover:text-white/70">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                        {mobile_open and (
                            <path d="M18 6L6 18M6 6l12 12"></path>
                        ) or (
                            <path d="M4 6h16M4 12h16M4 18h16"></path>
                        )}
                    </svg>
                </button>
            </div>

            {mobile_open and (
                <div className="md:hidden px-6 pb-4 space-y-0.5 border-t border-white/[0.04] bg-[#050507]/90 navbar-blur">
                    <button onClick={nav_features} className="block w-full text-left px-3 py-2.5 text-sm text-white/50 hover:text-white/80 transition-colors">Features</button>
                    <button onClick={nav_getting_started} className="block w-full text-left px-3 py-2.5 text-sm text-white/50 hover:text-white/80 transition-colors">Get Started</button>
                    <div className="pt-2">
                        <Button size="sm" onClick={handle_marketplace} className="w-full h-9 rounded-lg text-xs font-semibold">Install</Button>
                    </div>
                </div>
            )}
        </nav>
    );
}
