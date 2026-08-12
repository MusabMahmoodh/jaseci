import io;
import shutil;
import tarfile;
import tempfile;
import from pathlib { Path }
import from jaclang.scale.injector.bundle { _stage_app, pack_jab }


def _app_with_ignored_tree -> str {
    d = tempfile.mkdtemp(prefix="jac-jacignore-app-");
    Path(d, "jac.toml").write_text(
        "[project]\nname = \"app\"\n\n[scale]\nfat_bundle = false\n"
    );
    Path(d, "main.jac").write_text("def:pub ping -> str { return \"pong\"; }\n");
    junk = Path(d, "junk");
    junk.mkdir();
    Path(junk, "broken.jac").write_text("this is not valid jac\n");
    Path(d, ".jacignore").write_text("junk/\n");
    return d;
}


def _pod_binary -> bytes | None {
    jac_bin = Path(__file__).parents[4] / "zig-out" / "bin" / "jac";
    if not jac_bin.is_file() {
        return None;
    }
    return jac_bin.read_bytes();
}


def _names(raw: bytes) -> list[str] {
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as tar {
        return tar.getnames();
    }
}


test "the seal stage honors .jacignore, an ignored tree is never staged" {
    base = _app_with_ignored_tree();
    stage_root = _stage_app(Path(base), None);
    try {
        staged = sorted(
            str(p.relative_to(stage_root / "app"))
            for p in (stage_root / "app").rglob("*") if p.is_file()
        );
        assert "main.jac" in staged;
        assert not any(name.startswith("junk") for name in staged), (
            f"ignored tree was staged for the seal: {staged}"
        );
    } finally {
        shutil.rmtree(stage_root, ignore_errors=True);
        shutil.rmtree(base, ignore_errors=True);
    }
}


test "the .jab honors .jacignore, an ignored tree never ships to the pod" {
    seal_binary = _pod_binary();
    if seal_binary is None {
        # Same guard as test_fat_bundle: needs a built toolchain binary.
        return;
    }
    base = _app_with_ignored_tree();
    try {
        raw = pack_jab(base, seal_binary);
        names = _names(raw);
        assert any(name.endswith("main.jac") for name in names);
        assert not any(name.startswith("junk") for name in names), (
            f"ignored tree shipped in the bundle: {names}"
        );
    } finally {
        shutil.rmtree(base, ignore_errors=True);
    }
}
