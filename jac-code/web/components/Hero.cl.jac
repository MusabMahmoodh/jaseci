import from .ui.button { Button }

def:pub Hero() -> JsxElement {

    def handle_install_vsce() -> None {
        globalThis.open("https://marketplace.visualstudio.com/items?itemName=jaseci-labs.jaccoder", "_blank");
    }

    def handle_install_openvsx() -> None {
        globalThis.open("https://open-vsx.org/extension/jaseci-labs/jaccoder", "_blank");
    }

    def handle_get_started() -> None {
        el = globalThis.document.getElementById("getting-started");
        if el { el.scrollIntoView({"behavior": "smooth"}); }
    }

    return (
        <section className="relative min-h-screen flex items-center justify-center pt-28 pb-20 px-6 overflow-hidden">
            <div className="absolute inset-0 pointer-events-none">
                <div className="hero-gradient"></div>
            </div>

            <div className="relative max-w-6xl mx-auto w-full">
                <div className="text-center space-y-7 animate-fade-in-up mb-14">
                    <div className="section-label mx-auto w-fit">
                        <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse"></span>
                        Now available for VS Code
                    </div>

                    <h1 className="text-[3.25rem] md:text-[4rem] lg:text-[4.75rem] font-extrabold leading-[1.05] tracking-[-0.03em]">
                        <span className="gradient-text-subtle">Stop fighting</span>
                        <br />
                        <span className="gradient-text-subtle">AI polyglot.</span>
                        {" "}
                        <span className="gradient-text">Ship Jac.</span>
                    </h1>

                    <p className="text-white/50 text-base md:text-lg leading-relaxed max-w-xl mx-auto">
                        JacCoder understands your Jac codebase - nodes, walkers, graph architecture. It reads your AST, writes valid code, and validates every change.
                    </p>

                    <div className="flex flex-col sm:flex-row gap-3 pt-1 justify-center">
                        <Button size="lg" onClick={handle_install_vsce} className="inline-flex items-center justify-center gap-2.5 h-12 px-7 rounded-xl text-[0.9375rem] font-semibold shadow-[0_0_24px_-4px_rgba(249,115,22,0.3)]">
                            <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
                                <path d="M17.583 2.603L9.88 8.71 5.83 5.612l-1.83.925v10.933l1.837.918 4.043-3.09 7.703 6.107 2.417-1.18V3.783l-2.417-1.18zM9.56 15.291l-3.606 2.764V5.952l3.606 2.764v6.575zm8.023 3.073l-6.205-4.907V10.55l6.205-4.907v12.72z"/>
                            </svg>
                            Install for VS Code
                        </Button>
                        <Button variant="outline" size="lg" onClick={handle_install_openvsx} className="inline-flex items-center justify-center gap-2.5 h-12 px-7 rounded-xl text-[0.9375rem] font-semibold border-white/10 hover:border-white/20 hover:bg-white/[0.03]">
                            <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" className="text-white/70">
                                <path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/>
                            </svg>
                            Open VSX
                        </Button>
                    </div>
                </div>

                <div className="animate-fade-in-up animation-delay-300">
                    <div className="relative rounded-2xl overflow-hidden terminal-glow shadow-2xl shadow-orange-500/5 border border-white/[0.06]">
                        <img
                            src="static/assets/vsce.png"
                            alt="JacCoder VS Code Extension — AI coding agent for Jac"
                            className="w-full h-auto block"
                        />
                        <div className="absolute inset-0 rounded-2xl ring-1 ring-inset ring-white/[0.08] pointer-events-none"></div>
                    </div>
                </div>
            </div>
        </section>
    );
}
