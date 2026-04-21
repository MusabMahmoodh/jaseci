import from .ui.button { Button }


def:pub GettingStarted() -> JsxElement {

    def handle_marketplace() -> None {
        globalThis.open("https://marketplace.visualstudio.com/items?itemName=jaseci-labs.jaccoder", "_blank");
    }

    def handle_openvsx() -> None {
        globalThis.open("https://open-vsx.org/extension/jaseci-labs/jaccoder", "_blank");
    }

    def handle_playlist() -> None {
        globalThis.open("https://www.youtube.com/playlist?list=PLeSIxtqTjyZmd6Z8oaQX9KdOCtQSJfP6C", "_blank");
    }

    return (
        <section id="getting-started" className="relative py-32 px-6 section-glow">
            <div className="max-w-4xl mx-auto">
                <div className="text-center mb-16">
                    <div className="section-label mx-auto mb-5 w-fit">Get Started</div>
                    <h2 className="text-4xl md:text-5xl font-bold tracking-[-0.02em] mb-5">
                        <span className="gradient-text-subtle">Up and running in under a minute</span>
                    </h2>
                    <p className="text-white/40 text-base md:text-lg max-w-lg mx-auto leading-relaxed">
                        Install the VS Code extension and start building with Jac.
                    </p>
                </div>

                <div className="grid grid-cols-1 lg:grid-cols-2 gap-5 max-w-4xl mx-auto">

                    <div className="glass glass-primary spot-card p-8 md:p-10">
                        <div className="relative z-[2]">
                            <div className="flex items-center gap-3 mb-6">
                                <div className="w-11 h-11 rounded-xl bg-orange-500/8 border border-orange-500/12 flex items-center justify-center">
                                    <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" className="text-orange-400">
                                        <path d="M17.583 2.603L9.88 8.71 5.83 5.612l-1.83.925v10.933l1.837.918 4.043-3.09 7.703 6.107 2.417-1.18V3.783l-2.417-1.18zM9.56 15.291l-3.606 2.764V5.952l3.606 2.764v6.575zm8.023 3.073l-6.205-4.907V10.55l6.205-4.907v12.72z"/>
                                    </svg>
                                </div>
                                <div>
                                    <h3 className="text-lg font-semibold text-white">VS Code Extension</h3>
                                    <p className="text-white/30 text-xs">One click install</p>
                                </div>
                            </div>

                            <p className="text-white/35 text-sm mb-6 leading-relaxed">
                                Inline chat, real-time file diffs, and tool activity - directly inside your editor. JacCoder understands your codebase and writes valid Jac code.
                            </p>

                            <div className="space-y-3">
                                <Button size="lg" onClick={handle_marketplace} className="w-full justify-center gap-2 h-12 rounded-xl text-sm font-semibold shadow-[0_0_20px_-4px_rgba(249,115,22,0.25)]">
                                    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
                                        <path d="M17.583 2.603L9.88 8.71 5.83 5.612l-1.83.925v10.933l1.837.918 4.043-3.09 7.703 6.107 2.417-1.18V3.783l-2.417-1.18zM9.56 15.291l-3.606 2.764V5.952l3.606 2.764v6.575zm8.023 3.073l-6.205-4.907V10.55l6.205-4.907v12.72z"/>
                                    </svg>
                                    Install from VS Code Marketplace
                                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                                        <path d="M7 17L17 7M17 7H7M17 7v10"></path>
                                    </svg>
                                </Button>
                                <Button variant="outline" size="lg" onClick={handle_openvsx} className="w-full justify-center gap-2 h-12 rounded-xl text-sm font-semibold border-white/10 hover:border-white/20 hover:bg-white/[0.03]">
                                    Also available on Open VSX
                                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                                        <path d="M7 17L17 7M17 7H7M17 7v10"></path>
                                    </svg>
                                </Button>
                            </div>
                        </div>
                    </div>

                    <div className="glass spot-card p-8 md:p-10">
                        <div className="relative z-[2]">
                            <div className="flex items-center gap-3 mb-6">
                                <div className="w-11 h-11 rounded-xl bg-red-500/8 border border-red-500/12 flex items-center justify-center">
                                    <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" className="text-red-400">
                                        <path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/>
                                    </svg>
                                </div>
                                <div>
                                    <h3 className="text-lg font-semibold text-white">Watch: How to Install</h3>
                                    <p className="text-white/30 text-xs">Step-by-step video guide</p>
                                </div>
                            </div>

                            <div className="rounded-xl overflow-hidden border border-white/[0.06] mb-6">
                                <iframe
                                    width="100%"
                                    height="215"
                                    src="https://www.youtube.com/embed/xQKJml_WKGA?list=PLeSIxtqTjyZmd6Z8oaQX9KdOCtQSJfP6C"
                                    title="How to Install JacCoder"
                                    frameBorder="0"
                                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                                    allowFullScreen={True}
                                    className="block"
                                ></iframe>
                            </div>

                            <Button variant="outline" size="lg" onClick={handle_playlist} className="w-full justify-center gap-2 h-12 rounded-xl text-sm font-semibold border-white/10 hover:border-white/20 hover:bg-white/[0.03]">
                                <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" className="text-red-400">
                                    <path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/>
                                </svg>
                                Watch Full Tutorial Playlist
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                                    <path d="M7 17L17 7M17 7H7M17 7v10"></path>
                                </svg>
                            </Button>
                        </div>
                    </div>

                </div>
            </div>
        </section>
    );
}
