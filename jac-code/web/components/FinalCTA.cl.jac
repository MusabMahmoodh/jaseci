import from .ui.button { Button }


def:pub FinalCTA() -> JsxElement {
    def handle_install_vsce() -> None {
        globalThis.open("https://marketplace.visualstudio.com/items?itemName=jaseci-labs.jaccoder", "_blank");
    }

    def handle_install_openvsx() -> None {
        globalThis.open("https://open-vsx.org/extension/jaseci-labs/jaccoder", "_blank");
    }

    def handle_github() -> None {
        globalThis.open("https://github.com/Jaseci-Labs/jaseci", "_blank");
    }

    return (
        <section className="py-24 px-6">
            <div className="max-w-4xl mx-auto">
                <div className="cta-block">
                    <div className="relative p-12 md:p-20 text-center">
                        <h2 className="text-4xl md:text-5xl font-bold tracking-[-0.02em] mb-4">
                            <span className="gradient-text-subtle">Ready to ship Jac faster?</span>
                        </h2>
                        <p className="text-white/40 text-base md:text-lg max-w-md mx-auto mb-10 leading-relaxed">
                            Install JacCoder and let an agent that understands your codebase do the heavy lifting.
                        </p>
                        <div className="flex flex-col sm:flex-row items-center justify-center gap-3">
                            <Button size="lg" onClick={handle_install_vsce} className="inline-flex items-center gap-2.5 h-12 px-7 rounded-xl text-[0.9375rem] font-semibold shadow-[0_0_24px_-4px_rgba(249,115,22,0.3)]">
                                <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
                                    <path d="M17.583 2.603L9.88 8.71 5.83 5.612l-1.83.925v10.933l1.837.918 4.043-3.09 7.703 6.107 2.417-1.18V3.783l-2.417-1.18zM9.56 15.291l-3.606 2.764V5.952l3.606 2.764v6.575zm8.023 3.073l-6.205-4.907V10.55l6.205-4.907v12.72z"/>
                                </svg>
                                Install for VS Code
                            </Button>
                            <Button variant="outline" size="lg" onClick={handle_install_openvsx} className="inline-flex items-center gap-2.5 h-12 px-7 rounded-xl text-[0.9375rem] font-semibold border-white/10 hover:border-white/20 hover:bg-white/[0.03]">
                                <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" className="text-white/70">
                                    <path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/>
                                </svg>
                                Open VSX
                            </Button>
                        </div>
                    </div>
                </div>
            </div>
        </section>
    );
}
