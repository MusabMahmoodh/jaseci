"""Output area with drag-to-resize and collapse/expand.
Wraps the read-only log viewer (TerminalPanel)."""

import from react { useRef }
import from "...lib.utils" { cn }
import from "..ide.TerminalPanel" { TerminalPanel }

"""Output area with drag-to-resize."""
def:pub TerminalArea(props: Any) -> Any {
    content = props.content or "";
    isCollapsed = props.isCollapsed or False;
    onToggle = props.onToggle;
    onClear = props.onClear;

    has termHeight: int = 200;
    has isDragging: bool = False;

    startYRef = useRef(0);
    startHRef = useRef(0);

    def startResize(e: Any) -> None {
        e.preventDefault();
        e.stopPropagation();
        startYRef.current = e.clientY;
        startHRef.current = termHeight;
        isDragging = True;
        document.body.style.cursor = "row-resize";
        document.body.style.userSelect = "none";
    }

    def handleDragMove(e: Any) -> None {
        newH = startHRef.current - (e.clientY - startYRef.current);
        if newH < 100 { newH = 100; }
        if newH > 600 { newH = 600; }
        termHeight = newH;
    }

    def handleDragEnd(_: Any) -> None {
        isDragging = False;
        document.body.style.cursor = "";
        document.body.style.userSelect = "";
    }

    if isCollapsed {
        return <div className="flex-shrink-0">
            <div
                className="h-[30px] flex items-center justify-between pl-3 pr-2 border-t border-border bg-card cursor-pointer select-none"
                onClick={onToggle}
            >
                <div className="flex items-center gap-2">
                    <span className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">Output</span>
                </div>
            </div>
        </div>;
    }

    return <div className="flex-shrink-0 flex flex-col border-t border-border" style={{"height": String(termHeight) + "px"}}>
        {isDragging and <div
            className="fixed inset-0 z-[9999] cursor-row-resize"
            onMouseMove={handleDragMove}
            onMouseUp={handleDragEnd}
        /> or None}
        <div
            className="h-1 bg-border hover:bg-primary/35 cursor-row-resize transition-colors flex-shrink-0"
            onMouseDown={startResize}
        />
        <div className="h-[30px] flex items-center justify-between pl-1 pr-2 bg-card border-b border-border flex-shrink-0">
            <div className="flex items-center gap-0">
                <span className="flex items-center gap-1 px-2.5 h-[30px] text-[11px] font-medium border-b-2 border-primary text-foreground">
                    {"Output"}
                </span>
            </div>
            <div className="flex items-center gap-1">
                {onClear and <button
                    className="text-[10px] text-muted-foreground hover:text-foreground px-1.5 py-0.5 rounded hover:bg-muted transition-colors"
                    onClick={onClear}
                >
                    {"Clear"}
                </button> or None}
                <button
                    className="text-[10px] text-muted-foreground hover:text-foreground px-1.5 py-0.5 rounded hover:bg-muted transition-colors"
                    onClick={onToggle}
                >
                    {"Collapse"}
                </button>
            </div>
        </div>
        <div className="flex-1 min-h-0 overflow-hidden">
            <TerminalPanel
                content={content}
                isCollapsed={False}
                onToggle={onToggle}
                onClear={onClear}
                hideHeader={True}
            />
        </div>
    </div>;
}
