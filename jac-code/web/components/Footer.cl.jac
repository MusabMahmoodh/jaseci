def:pub Footer() -> JsxElement {
    def go(url: str) -> None {
        globalThis.open(url, "_blank");
    }

    def handle_github() -> None { go("https://github.com/Jaseci-Labs/jaseci"); }
    def handle_docs() -> None { go("https://docs.jaseci.org"); }
    def handle_marketplace() -> None { go("https://marketplace.visualstudio.com/items?itemName=jaseci-labs.jaccoder"); }
    def handle_openvsx() -> None { go("https://open-vsx.org/extension/jaseci-labs/jaccoder"); }
    def handle_discord() -> None { go("https://discord.gg/jaseci"); }

    def scroll_to(id: str) -> None {
        el = globalThis.document.getElementById(id);
        if el { el.scrollIntoView({"behavior": "smooth"}); }
    }

    def nav_features() -> None { scroll_to("features"); }
    def nav_start() -> None { scroll_to("getting-started"); }

    return (
        <footer className="border-t border-white/[0.04] pt-14 pb-8 px-6 relative">
            <div className="max-w-6xl mx-auto">
                <div className="grid grid-cols-2 md:grid-cols-4 gap-8 mb-14">
                    <div className="col-span-2 md:col-span-1">
                        <div className="flex items-center gap-2 mb-3">
                            <img src="/static/assets/jaseci_logo.png" alt="JacCoder" className="w-6 h-6" />
                            <span className="text-sm font-bold gradient-text">JacCoder</span>
                        </div>
                        <p className="text-white/25 text-xs leading-relaxed max-w-[180px]">
                            AI coding agent for the Jaseci stack.
                        </p>
                    </div>

                    <div>
                        <h4 className="text-xs font-semibold text-white/50 uppercase tracking-wider mb-3">Product</h4>
                        <div className="space-y-2">
                            <button onClick={nav_features} className="block text-xs text-white/30 hover:text-white/60 transition-colors">Features</button>
                            <button onClick={nav_start} className="block text-xs text-white/30 hover:text-white/60 transition-colors">Get Started</button>
                        </div>
                    </div>

                    <div>
                        <h4 className="text-xs font-semibold text-white/50 uppercase tracking-wider mb-3">Resources</h4>
                        <div className="space-y-2">
                            <button onClick={handle_docs} className="block text-xs text-white/30 hover:text-white/60 transition-colors">Documentation</button>
                            <button onClick={handle_marketplace} className="block text-xs text-white/30 hover:text-white/60 transition-colors">VS Code Marketplace</button>
                            <button onClick={handle_openvsx} className="block text-xs text-white/30 hover:text-white/60 transition-colors">Open VSX</button>
                        </div>
                    </div>

                    <div>
                        <h4 className="text-xs font-semibold text-white/50 uppercase tracking-wider mb-3">Community</h4>
                        <div className="space-y-2">
                            <button onClick={handle_discord} className="block text-xs text-white/30 hover:text-white/60 transition-colors">Discord</button>
                            <button onClick={handle_github} className="block text-xs text-white/30 hover:text-white/60 transition-colors">Contribute</button>
                        </div>
                    </div>
                </div>

                <div className="border-t border-white/[0.04] pt-6 flex flex-col sm:flex-row items-center justify-between gap-3">
                    <p className="text-white/15 text-[0.6875rem]">
                        {"© 2026 Jaseci Labs. All rights reserved."}
                    </p>
                    <p className="text-white/15 text-[0.6875rem]">
                        Built with Jaseci
                    </p>
                </div>
            </div>
        </footer>
    );
}
