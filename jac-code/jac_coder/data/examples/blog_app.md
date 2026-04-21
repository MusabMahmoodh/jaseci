# Example: Blog with Posts & Comments

Fullstack blog with related data models (Post → Comment), walker endpoint, service layer, dynamic routing.

## Project Structure

```
blog-app/
├── jac.toml
├── main.jac                      # Entry: imports backend + cl { app() }
├── services/
│   ├── blogService.sv.jac        # Backend: Post/Comment nodes + endpoints
│   └── apiService.cl.jac         # Frontend service layer (error handling)
├── hooks/
│   ├── usePosts.cl.jac           # Posts hook
│   └── useComments.cl.jac        # Comments hook
├── components/
│   ├── Layout.cl.jac             # Root layout with Outlet
│   ├── Header.cl.jac             # Nav bar
│   ├── PostCard.cl.jac           # Post summary
│   ├── PostForm.cl.jac           # Create post form
│   └── CommentList.cl.jac        # Comments + add form
├── pages/
│   ├── layout.jac                # Root nav
│   ├── index.jac                 # Home — post list
│   └── posts/[id].jac            # Single post (dynamic)
└── styles/global.css
```

## main.jac — Entry Point

Imports backend endpoints from `.sv.jac` to register them, then mounts the client.

```jac
import from services.blogService {
    get_posts, get_post, create_post, delete_post,
    get_comments, add_comment, get_post_with_comments
}

# File-based routing: app() must accept `children` and render them.
# Without `children: Any = None`, routed pages get discarded silently.
cl {
    def:pub app(children: Any = None) -> JsxElement {
        return <>{children}</>;
    }
}
```

## services/blogService.sv.jac — Backend (Nodes + Endpoints)

```jac
import from datetime { datetime }

node Post {
    has title: str = "";
    has body: str = "";
    has author: str = "";
    has category: str = "";
    has created_at: str = "";

    def postinit {
        if not self.created_at { self.created_at = datetime.now().isoformat(); }
    }
}

node Comment {
    has author: str = "";
    has text: str = "";
    has created_at: str = "";

    def postinit {
        if not self.created_at { self.created_at = datetime.now().isoformat(); }
    }
}

# --- Post CRUD (typed returns) ---

def:pub get_posts(category: str = "") -> list[Post] {
    all_posts = [root()-->][?:Post];
    if category {
        all_posts = [p for p in all_posts if p.category == category];
    }
    return all_posts;
}

def:pub get_post(post_id: str) -> Post {
    for p in [root()-->][?:Post] {
        if jid(p) == post_id { return p; }
    }
}

def:pub create_post(title: str, body: str, author: str = "", category: str = "") -> Post {
    return (root() ++> Post(title=title, body=body, author=author, category=category))[0];
}

def:pub delete_post(post_id: str) -> dict {
    for p in [root()-->][?:Post] {
        if jid(p) == post_id {
            for c in [p-->][?:Comment] { p del--> c; }
            root() del--> p;
            return {"success": True};
        }
    }
    return {"success": False, "error": "Not found"};
}

# --- Comment CRUD (child nodes of Post, typed returns) ---

def:pub get_comments(post_id: str) -> list[Comment] {
    for p in [root()-->][?:Post] {
        if jid(p) == post_id {
            return [p-->][?:Comment];
        }
    }
    return [];
}

def:pub add_comment(post_id: str, author: str, text: str) -> Comment {
    for p in [root()-->][?:Post] {
        if jid(p) == post_id {
            return (p ++> Comment(author=author, text=text))[0];
        }
    }
}

# --- Walker endpoint (single-request post + comments) ---

walker :pub get_post_with_comments {
    has post_id: str = "";

    can find_post with Root entry {
        for p in [-->][?:Post] {
            if jid(p) == self.post_id { visit p; return; }
        }
        report {"error": "Post not found"};
    }

    can collect with Post entry {
        comments = [{"id": jid(c), "author": c.author, "text": c.text}
                    for c in [-->][?:Comment]];
        report {
            "post": {"id": jid(here), "title": here.title, "body": here.body},
            "comments": comments
        };
    }
}
```

## services/apiService.cl.jac — Frontend Service Layer

```jac
sv import from .blogService { get_posts, get_post, create_post, delete_post, get_comments, add_comment }

async def:pub fetchPosts(category: str = "") -> any {
    try {
        posts = await get_posts(category);
        return {"success": True, "posts": posts or []};
    } except Exception as e {
        return {"success": False, "error": str(e), "posts": []};
    }
}

async def:pub fetchPost(postId: str) -> any {
    try {
        post = await get_post(postId);
        if post {
            return {"success": True, "post": post};
        }
        return {"success": False, "error": "Not found"};
    } except Exception as e {
        return {"success": False, "error": str(e)};
    }
}

async def:pub submitPost(title: str, body: str, author: str = "", category: str = "") -> any {
    try {
        result = await create_post(title, body, author, category);
        return {"success": True, "post": result};
    } except Exception as e {
        return {"success": False, "error": str(e)};
    }
}

async def:pub fetchComments(postId: str) -> any {
    try {
        comments = await get_comments(postId);
        return {"success": True, "comments": comments or []};
    } except Exception as e {
        return {"success": False, "error": str(e), "comments": []};
    }
}

async def:pub submitComment(postId: str, author: str, text: str) -> any {
    try {
        result = await add_comment(postId, author, text);
        if result {
            return {"success": True, "comment": result};
        }
        return {"success": False, "error": "Failed"};
    } except Exception as e {
        return {"success": False, "error": str(e)};
    }
}
```

## hooks/usePosts.cl.jac

```jac
import from ..services.apiService { fetchPosts, submitPost }

def:pub usePosts() -> dict {
    has posts: list = [];
    has isLoading: bool = True;
    has error: str = "";
    has selectedCategory: str = "";

    async can with entry { await loadPosts(); }
    async can with [selectedCategory] entry { await loadPosts(); }

    async def loadPosts() -> None {
        isLoading = True;
        error = "";
        result = await fetchPosts(selectedCategory);
        if result["success"] { posts = result["posts"]; }
        else { error = result["error"] or "Failed"; }
        isLoading = False;
    }

    async def handleCreate(title: str, body: str, category: str = "") -> bool {
        result = await submitPost(title, body, "", category);
        if result["success"] { await loadPosts(); return True; }
        return False;
    }

    def setCategory(cat: str) -> None { selectedCategory = cat; }

    return {
        "posts": posts, "isLoading": isLoading, "error": error,
        "selectedCategory": selectedCategory,
        "setCategory": setCategory, "handleCreate": handleCreate
    };
}
```

## hooks/useComments.cl.jac

```jac
import from ..services.apiService { fetchComments, submitComment }

def:pub useComments(postId: str) -> dict {
    has comments: list = [];
    has isLoading: bool = True;

    async can with entry { await loadComments(); }

    async def loadComments() -> None {
        isLoading = True;
        result = await fetchComments(postId);
        if result["success"] { comments = result["comments"]; }
        isLoading = False;
    }

    async def handleAdd(author: str, text: str) -> bool {
        result = await submitComment(postId, author, text);
        if result["success"] {
            comments = comments + [result["comment"]];
            return True;
        }
        return False;
    }

    return {"comments": comments, "isLoading": isLoading, "handleAdd": handleAdd};
}
```

## components/PostCard.cl.jac

```jac
import from "@jac/runtime" { Link }

def:pub PostCard(props: dict) -> JsxElement {
    onDelete = props["onDelete"] or None;

    # Props are always dict — extract values
    postId = props["postId"] or "";
    title = props["title"] or "Untitled";
    body = props["body"] or "";
    category = props["category"] or "";

    preview = body;
    if len(body) > 150 { preview = body[0:150] + "..."; }

    def handle_delete() -> None { onDelete(postId); }

    return <div className="border rounded-xl p-5 mb-4 bg-white">
        <Link to={"/posts/" + postId} className="text-xl font-semibold">{title}</Link>
        {category and (<span className="ml-2 text-xs bg-blue-100 text-blue-600 px-2 py-1 rounded-full">{category}</span>)}
        <p className="text-gray-500 mt-2">{preview}</p>
        <div className="flex justify-between items-center mt-3 text-sm text-gray-400">
            {onDelete and (<button onClick={handle_delete} className="text-red-500">Delete</button>)}
        </div>
    </div>;
}
```

## components/CommentList.cl.jac

```jac
import from ..hooks.useComments { useComments }

def:pub CommentList(props: dict) -> JsxElement {
    postId = props["postId"] or "";
    data = useComments(postId);
    comments = data["comments"] or [];

    has newAuthor: str = "";
    has newText: str = "";

    async def handleSubmit(e: any) -> None {
        e.preventDefault();
        if not newAuthor.strip() or not newText.strip() { return; }
        success = await data["handleAdd"](newAuthor.strip(), newText.strip());
        if success { newAuthor = ""; newText = ""; }
    }

    def handle_author(e: any) -> None { newAuthor = e.target.value; }
    def handle_text(e: any) -> None { newText = e.target.value; }

    return <div className="mt-6">
        <h3 className="font-semibold mb-3">{"Comments (" + str(len(comments)) + ")"}</h3>
        {data["isLoading"] and (<p className="text-gray-400">Loading...</p>)}
        {[
            <div key={jid(c)} className="p-3 bg-gray-50 rounded mb-2">
                <strong>{c.author}</strong>
                <p className="text-gray-600 mt-1">{c.text}</p>
            </div>
            for c in comments
        ]}
        <form onSubmit={handleSubmit} className="flex gap-2 mt-3">
            <input value={newAuthor} onChange={handle_author} placeholder="Name" className="px-3 py-2 border rounded w-28" />
            <input value={newText} onChange={handle_text} placeholder="Comment..." className="px-3 py-2 border rounded flex-1" />
            <button type="submit" className="px-4 py-2 bg-blue-500 text-white rounded">Post</button>
        </form>
    </div>;
}
```

## pages/posts/[id].jac — Dynamic Route

```jac
import from "@jac/runtime" { useParams, Link }
import from ...services.apiService { fetchPost }
import from ...components.CommentList { CommentList }

def:pub page() -> JsxElement {
    params = useParams();
    postId = params.id or "";

    has post: dict = {};
    has isLoading: bool = True;
    has error: str = "";

    async can with entry {
        result = await fetchPost(postId);
        if result["success"] { post = result["post"]; }
        else { error = result["error"] or "Not found"; }
        isLoading = False;
    }

    if isLoading { return <p className="text-center py-10 text-gray-400">Loading...</p>; }
    if error {
        return <div className="text-center py-10">
            <p className="text-red-500">{error}</p>
            <Link to="/" className="text-blue-500">Back to posts</Link>
        </div>;
    }

    return <div>
        <Link to="/" className="text-blue-500 text-sm">Back to posts</Link>
        <h1 className="text-3xl font-bold mt-4">{post["title"] or ""}</h1>
        <div className="mt-5 leading-relaxed whitespace-pre-wrap">{post["body"] or ""}</div>
        <CommentList postId={postId} />
    </div>;
}
```

## pages/layout.jac — Root Layout

```jac
cl import from "@jac/runtime" { Outlet, Link }

cl {
    def:pub layout() -> JsxElement {
        return (
            <div className="min-h-screen bg-gray-50">
                <nav className="bg-white border-b px-6 py-4">
                    <Link to="/" className="text-xl font-bold">Blog</Link>
                </nav>
                <main className="max-w-3xl mx-auto px-4 py-6">
                    <Outlet />
                </main>
            </div>
        );
    }
}
```

## pages/index.jac — Home (post list + create form)

```jac
cl import from ..hooks.usePosts { usePosts }
cl import from ..components.PostCard { PostCard }

cl {
    def:pub page() -> JsxElement {
        has newTitle: str = "";
        has newBody: str = "";

        data = usePosts();
        posts = data["posts"] or [];
        isLoading = data["isLoading"] or False;
        error = data["error"] or "";
        handleCreate = data["handleCreate"];

        async def on_submit(e: any) -> None {
            e.preventDefault();
            if not newTitle.strip() or not newBody.strip() { return; }
            success = await handleCreate(newTitle.strip(), newBody.strip(), "");
            if success { newTitle = ""; newBody = ""; }
        }

        def handle_title(e: any) -> None { newTitle = e.target.value; }
        def handle_body(e: any) -> None { newBody = e.target.value; }

        return (
            <div>
                <h1 className="text-2xl font-bold mb-4">Posts</h1>

                <form onSubmit={on_submit} className="bg-white border rounded p-4 mb-6 flex flex-col gap-2">
                    <input value={newTitle} onChange={handle_title} placeholder="Title" className="px-3 py-2 border rounded" />
                    <textarea value={newBody} onChange={handle_body} placeholder="Body" rows={4} className="px-3 py-2 border rounded" />
                    <button type="submit" className="self-start px-4 py-2 bg-blue-500 text-white rounded">Create</button>
                </form>

                {error and (<p className="text-red-500 mb-4">{error}</p>)}
                {isLoading and (<p className="text-gray-400">Loading...</p>)}

                {[<PostCard key={jid(p)} postId={jid(p)} title={p.title} body={p.body} category={p.category} /> for p in posts]}
            </div>
        );
    }
}
```

## styles/global.css

```css
@import "tailwindcss";
```

## jac.toml

```toml
[project]
name = "blog_app"
version = "1.0.0"
description = "Jac full-stack blog"
entry-point = "main.jac"

[dependencies]

[dependencies.npm]
clsx = "^2.1.1"
tailwind-merge = "^3.4.0"
tailwindcss = "^4.1.17"
react = "^18.2.0"
react-dom = "^18.2.0"
react-router-dom = "^6.22.0"
react-error-boundary = "^5.0.0"
react-hook-form = "^7.71.0"
zod = "^4.3.6"
"@hookform/resolvers" = "^5.2.2"

[dependencies.npm.dev]
"@tailwindcss/vite" = "^4.1.17"
vite = "^6.4.1"
"@vitejs/plugin-react" = "^4.2.1"
typescript = "^5.3.3"
"@types/react" = "^18.2.0"
"@types/react-dom" = "^18.2.0"

[serve]
base_route_app = "app"

[plugins.client.vite]
plugins = ["tailwindcss()"]
lib_imports = ["import tailwindcss from '@tailwindcss/vite'"]

[plugins.client.app_meta_data]
title = "Blog App"
```
