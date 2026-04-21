# Example: Blog with Posts & Comments

A full-stack blog with multiple related data models (Post → Comment), walker endpoints, service layer, and dynamic routing.

### Project Structure

```
blog-app/
├── jac.toml
├── main.jac                          # ALL backend (nodes, endpoints, walker) + cl { app() }
├── services/
│   └── apiService.cl.jac             # Frontend: service layer
├── hooks/
│   ├── usePosts.cl.jac               # Posts data hook
│   └── useComments.cl.jac            # Comments data hook
├── components/
│   ├── Layout.cl.jac                 # Root layout — imports Outlet, minimal wrapper
│   ├── Header.cl.jac                 # Nav/header bar
│   ├── PostCard.cl.jac               # Post summary card
│   ├── PostForm.cl.jac               # Create post form
│   └── CommentList.cl.jac            # Comments + add form
├── pages/
│   ├── layout.jac                    # Root layout with nav
│   ├── index.jac                     # Home — post list
│   └── posts/[id].jac               # Single post (dynamic route)
└── styles/global.css
```

### jac.toml

```jac
[project]
name = "blog-app"
version = "1.0.0"
entry-point = "main.jac"

[dependencies.npm.dev]
"@jac-client/dev-deps" = "1.0.0"

[serve]
base_route_app = "app"

[plugins.client]
```

### main.jac — All backend + frontend entry

```jac
"""Blog app — all backend code (nodes, endpoints, walker) + frontend entry.
All backend code goes in main.jac. Nodes connected to root auto-persist in SQLite.
"""
import from uuid {uuid4}
import from datetime {datetime}

# Data models — nodes connected to root auto-persist
node Post {
    has id: str;
    has title: str;
    has body: str;
    has author: str = "";
    has category: str = "";
    has created_at: str = "";
}

node Comment {
    has id: str;
    has author: str;
    has text: str;
    has created_at: str = "";
}

# --- Public CRUD endpoints (def:pub) ---

def:pub get_posts(category: str = "") -> list {
    """Get all posts, optionally filtered by category."""
    all_posts = [root-->][?:Post];
    if category {
        all_posts = [p for p in all_posts if p.category == category];
    }
    return [
        {"id": p.id, "title": p.title, "body": p.body,
         "author": p.author, "category": p.category,
         "created_at": p.created_at,
         "comment_count": len([p-->][?:Comment])}
        for p in all_posts
    ];
}

def:pub get_post(post_id: str) -> dict {
    """Get a single post by ID."""
    for p in [root-->][?:Post] {
        if p.id == post_id {
            return {"id": p.id, "title": p.title, "body": p.body,
                    "author": p.author, "category": p.category,
                    "created_at": p.created_at};
        }
    }
    return {"error": "Post not found"};
}

def:pub create_post(title: str, body: str, author: str = "", category: str = "") -> dict {
    """Create a new post."""
    post = root ++> Post(
        id=str(uuid4()), title=title, body=body,
        author=author, category=category,
        created_at=datetime.now().isoformat()
    );
    return {"id": post.id, "title": post.title};
}

def:pub delete_post(post_id: str) -> dict {
    """Delete a post and its comments."""
    for p in [root-->][?:Post] {
        if p.id == post_id {
            for c in [p-->][?:Comment] { p del--> c; }
            root del--> p;
            return {"success": True};
        }
    }
    return {"success": False, "error": "Not found"};
}

# --- Comments (child nodes of Post) ---

def:pub get_comments(post_id: str) -> list {
    """Get comments for a post."""
    for p in [root-->][?:Post] {
        if p.id == post_id {
            return [{"id": c.id, "author": c.author, "text": c.text,
                     "created_at": c.created_at}
                    for c in [p-->][?:Comment]];
        }
    }
    return [];
}

def:pub add_comment(post_id: str, author: str, text: str) -> dict {
    """Add a comment to a post."""
    for p in [root-->][?:Post] {
        if p.id == post_id {
            comment = p ++> Comment(
                id=str(uuid4()), author=author, text=text,
                created_at=datetime.now().isoformat()
            );
            return {"id": comment.id, "author": comment.author, "text": comment.text};
        }
    }
    return {"error": "Post not found"};
}

def:pub delete_comment(post_id: str, comment_id: str) -> dict {
    """Delete a comment."""
    for p in [root-->][?:Post] {
        if p.id == post_id {
            for c in [p-->][?:Comment] {
                if c.id == comment_id {
                    p del--> c;
                    return {"success": True};
                }
            }
        }
    }
    return {"success": False, "error": "Not found"};
}

# --- Walker endpoint (multi-node traversal in one request) ---

walker :pub get_post_with_comments {
    """Traverse Post → Comments in a single request."""
    has post_id: str;

    obj __specs__ {
        static has methods: list = ["post"];
    }

    can find_post with Root entry {
        for p in [-->][?:Post] {
            if p.id == self.post_id {
                visit p;
                return;
            }
        }
        report {"error": "Post not found"};
    }

    can collect with Post entry {
        comments = [{"id": c.id, "author": c.author, "text": c.text,
                     "created_at": c.created_at}
                    for c in [-->][?:Comment]];
        report {
            "post": {"id": here.id, "title": here.title, "body": here.body,
                     "author": here.author, "category": here.category},
            "comments": comments,
            "comment_count": len(comments)
        };
    }
}


# Frontend entry
cl import from .components.Layout { Layout }
cl {
    def:pub app() -> JsxElement {
        return <Layout />;
    }
}
```

### Frontend Service: services/apiService.cl.jac

```jac
"""Service layer — wraps sv import and walker calls with error handling."""

sv import from ..main { get_posts, get_post, create_post, delete_post,
                         get_comments, add_comment, delete_comment,
                         get_post_with_comments }

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
        if post and not post.error {
            return {"success": True, "post": post};
        }
        return {"success": False, "error": post.error or "Not found"};
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

async def:pub removePost(postId: str) -> any {
    try {
        result = await delete_post(postId);
        return {"success": result.success or False};
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
        if result and not result.error {
            return {"success": True, "comment": result};
        }
        return {"success": False, "error": result.error or "Failed"};
    } except Exception as e {
        return {"success": False, "error": str(e)};
    }
}

async def:pub fetchPostWithComments(postId: str) -> any {
    """Use walker for single-request post + comments."""
    try {
        response = root spawn get_post_with_comments(post_id=postId);
        result = response.reports[len(response.reports) - 1]
            if response.reports and len(response.reports) > 0 else {};
        if result and not result.error {
            return {"success": True, "post": result.post, "comments": result.comments or []};
        }
        return {"success": False, "error": result.error or "Not found"};
    } except Exception as e {
        return {"success": False, "error": str(e)};
    }
}
```

### Hook: hooks/usePosts.cl.jac

```jac
"""Hook for managing posts state."""

import from ..services.apiService { fetchPosts, submitPost, removePost }

def:pub usePosts() -> dict {
    has posts: list = [];
    has isLoading: bool = False;
    has error: str = "";
    has selectedCategory: str = "";

    # Load posts on mount
    async can with entry {
        await loadPosts();
    }

    # Reload when category changes
    async can with [selectedCategory] entry {
        await loadPosts();
    }

    async def loadPosts() -> None {
        isLoading = True;
        error = "";
        result = await fetchPosts(selectedCategory);
        if result.success {
            posts = result.posts;
        } else {
            error = result.error or "Failed to load posts";
        }
        isLoading = False;
    }

    async def handleCreatePost(title: str, body: str, category: str = "") -> bool {
        result = await submitPost(title, body, "", category);
        if result.success {
            await loadPosts();
            return True;
        }
        return False;
    }

    async def handleDeletePost(postId: str) -> None {
        result = await removePost(postId);
        if result.success {
            posts = [p for p in posts if p["id"] != postId];
        }
    }

    def setCategory(cat: str) -> None {
        selectedCategory = cat;
    }

    return {
        "posts": posts,
        "isLoading": isLoading,
        "error": error,
        "selectedCategory": selectedCategory,
        "setCategory": setCategory,
        "handleCreatePost": handleCreatePost,
        "handleDeletePost": handleDeletePost,
        "refreshPosts": loadPosts
    };
}
```

### Hook: hooks/useComments.cl.jac

```jac
"""Hook for managing comments on a single post."""

import from ..services.apiService { fetchComments, submitComment }

def:pub useComments(postId: str) -> dict {
    has comments: list = [];
    has isLoading: bool = False;

    async can with entry {
        await loadComments();
    }

    async def loadComments() -> None {
        isLoading = True;
        result = await fetchComments(postId);
        if result.success {
            comments = result.comments;
        }
        isLoading = False;
    }

    async def handleAddComment(author: str, text: str) -> bool {
        result = await submitComment(postId, author, text);
        if result.success {
            comments = comments + [result.comment];
            return True;
        }
        return False;
    }

    return {
        "comments": comments,
        "isLoading": isLoading,
        "handleAddComment": handleAddComment,
        "refreshComments": loadComments
    };
}
```

### Component: components/Layout.cl.jac — Root Layout

```jac
"""Layout — imports Outlet for page routing, minimal wrapper."""

cl import from "@jac/runtime" { Outlet }
import from ".Header" { Header }

def:pub Layout() -> JsxElement {
    return (
        <div style={{"minHeight": "100vh", "background": "#f8fafc"}}>
            <Header />
            <main style={{"maxWidth": "768px", "margin": "0 auto", "padding": "24px"}}>
                <Outlet />
            </main>
        </div>
    );
}
```

### Component: components/Header.cl.jac

```jac
"""Nav/header bar for the blog."""

cl import from "@jac/runtime" { Link }

def:pub Header() -> JsxElement {
    return (
        <header style={{"borderBottom": "1px solid #e5e7eb", "padding": "16px 24px",
                         "display": "flex", "justifyContent": "space-between", "alignItems": "center",
                         "background": "white"}}>
            <Link to="/" style={{"fontSize": "20px", "fontWeight": "700", "color": "#1f2937",
                                  "textDecoration": "none"}}>
                Blog
            </Link>
            <nav style={{"display": "flex", "gap": "16px"}}>
                <Link to="/" style={{"color": "#6b7280", "textDecoration": "none"}}>Home</Link>
            </nav>
        </header>
    );
}
```

### Component: components/PostCard.cl.jac

```jac
"""Displays a single post summary card."""

cl import from "@jac/runtime" { Link }

def:pub PostCard(props: dict) -> JsxElement {
    post = props.post or {};
    onDelete = props.onDelete or None;

    postId = post["id"] or "";
    title = post["title"] or "Untitled";
    body = post["body"] or "";
    category = post["category"] or "";
    commentCount = post["comment_count"] or 0;

    preview = body;
    if len(body) > 150 {
        preview = body[0:150] + "...";
    }

    def handle_delete() -> None {
        onDelete(postId);
    }

    return <div style={{
        "border": "1px solid #e5e7eb", "borderRadius": "12px",
        "padding": "20px", "marginBottom": "16px", "background": "white"
    }}>
        <div style={{"display": "flex", "justifyContent": "space-between", "alignItems": "start"}}>
            <Link to={"/posts/" + postId}
                  style={{"fontSize": "20px", "fontWeight": "600", "color": "#1f2937",
                          "textDecoration": "none"}}>
                {title}
            </Link>
            {category and (
                <span style={{"padding": "4px 12px", "borderRadius": "16px",
                              "background": "#eff6ff", "color": "#3b82f6", "fontSize": "12px"}}>
                    {category}
                </span>
            )}
        </div>
        <p style={{"color": "#6b7280", "margin": "8px 0", "lineHeight": "1.5"}}>{preview}</p>
        <div style={{"display": "flex", "justifyContent": "space-between", "alignItems": "center"}}>
            <span style={{"color": "#9ca3af", "fontSize": "13px"}}>
                {str(commentCount) + " comments"}
            </span>
            {onDelete and (
                <button onClick={handle_delete}
                        style={{"color": "#ef4444", "background": "none", "border": "none",
                                "cursor": "pointer", "fontSize": "13px"}}>
                    Delete
                </button>
            )}
        </div>
    </div>;
}
```

### Component: components/PostForm.cl.jac

```jac
"""Form for creating a new post."""

def:pub PostForm(props: dict) -> JsxElement {
    onSubmit = props.onSubmit;

    has title: str = "";
    has body: str = "";
    has category: str = "";
    has isSubmitting: bool = False;

    async def handleSubmit(e: any) -> None {
        e.preventDefault();
        if not title.strip() or not body.strip() { return; }
        isSubmitting = True;
        success = await onSubmit(title.strip(), body.strip(), category.strip());
        if success {
            title = "";
            body = "";
            category = "";
        }
        isSubmitting = False;
    }

    def handle_title_change(e: any) -> None {
        title = e.target.value;
    }
    def handle_body_change(e: any) -> None {
        body = e.target.value;
    }
    def handle_category_change(e: any) -> None {
        category = e.target.value;
    }

    return <form onSubmit={handleSubmit} style={{
        "display": "flex", "flexDirection": "column", "gap": "12px",
        "padding": "20px", "border": "1px solid #e5e7eb", "borderRadius": "12px",
        "background": "white"
    }}>
        <input value={title}
               onChange={handle_title_change}
               placeholder="Post title"
               style={{"padding": "10px", "border": "1px solid #d1d5db",
                       "borderRadius": "8px", "fontSize": "16px"}} />
        <textarea value={body}
                  onChange={handle_body_change}
                  placeholder="Write your post..."
                  rows={4}
                  style={{"padding": "10px", "border": "1px solid #d1d5db",
                          "borderRadius": "8px", "fontSize": "14px", "resize": "vertical"}} />
        <input value={category}
               onChange={handle_category_change}
               placeholder="Category (optional)"
               style={{"padding": "10px", "border": "1px solid #d1d5db",
                       "borderRadius": "8px", "fontSize": "14px"}} />
        <button type="submit" disabled={isSubmitting or not title or not body}
                style={{"padding": "10px 20px", "background": "#3b82f6", "color": "white",
                        "border": "none", "borderRadius": "8px", "cursor": "pointer",
                        "fontSize": "14px", "fontWeight": "500"}}>
            {(isSubmitting and "Publishing..." or "Publish Post")}
        </button>
    </form>;
}
```

### Component: components/CommentList.cl.jac

```jac
"""Displays comments and add-comment form for a post."""

import from ..hooks.useComments { useComments }

def:pub CommentList(props: dict) -> JsxElement {
    postId = props.postId or "";
    commentData = useComments(postId);
    comments = commentData["comments"] or [];
    isLoading = commentData["isLoading"] or False;
    handleAddComment = commentData["handleAddComment"];

    has newAuthor: str = "";
    has newText: str = "";

    async def handleSubmitComment(e: any) -> None {
        e.preventDefault();
        if not newAuthor.strip() or not newText.strip() { return; }
        success = await handleAddComment(newAuthor.strip(), newText.strip());
        if success {
            newAuthor = "";
            newText = "";
        }
    }

    def handle_author_change(e: any) -> None {
        newAuthor = e.target.value;
    }
    def handle_text_change(e: any) -> None {
        newText = e.target.value;
    }

    return <div style={{"marginTop": "24px"}}>
        <h3 style={{"fontSize": "16px", "fontWeight": "600", "marginBottom": "12px"}}>
            {"Comments (" + str(len(comments)) + ")"}
        </h3>

        {isLoading and (<p style={{"color": "#9ca3af"}}>Loading comments...</p>)}

        {len(comments) > 0 and (
            <div style={{"display": "flex", "flexDirection": "column", "gap": "8px",
                         "marginBottom": "16px"}}>
                {[
                    <div key={c["id"]}
                         style={{"padding": "12px", "background": "#f9fafb",
                                 "borderRadius": "8px"}}>
                        <strong style={{"color": "#374151"}}>{c["author"]}</strong>
                        <p style={{"color": "#6b7280", "margin": "4px 0 0"}}>{c["text"]}</p>
                    </div>
                    for c in comments
                ]}
            </div>
        )}

        <form onSubmit={handleSubmitComment}
              style={{"display": "flex", "gap": "8px", "alignItems": "end"}}>
            <input value={newAuthor}
                   onChange={handle_author_change}
                   placeholder="Your name"
                   style={{"padding": "8px", "border": "1px solid #d1d5db",
                           "borderRadius": "6px", "width": "120px"}} />
            <input value={newText}
                   onChange={handle_text_change}
                   placeholder="Add a comment..."
                   style={{"padding": "8px", "border": "1px solid #d1d5db",
                           "borderRadius": "6px", "flex": "1"}} />
            <button type="submit" disabled={not newAuthor or not newText}
                    style={{"padding": "8px 16px", "background": "#3b82f6", "color": "white",
                            "border": "none", "borderRadius": "6px", "cursor": "pointer"}}>
                Post
            </button>
        </form>
    </div>;
}
```

### Page: pages/index.jac — Post List (Home)

```jac
"""Home page — lists all posts with category filter."""

import from ..hooks.usePosts { usePosts }
import from ..components.PostCard { PostCard }
import from ..components.PostForm { PostForm }

def:pub index() -> JsxElement {
    postData = usePosts();
    posts = postData["posts"] or [];
    isLoading = postData["isLoading"] or False;
    selectedCategory = postData["selectedCategory"] or "";

    has showForm: bool = False;

    categories = ["", "Tech", "Design", "Business"];

    def toggle_form() -> None {
        showForm = not showForm;
    }

    def handle_category_click(cat: str) -> None {
        postData["setCategory"](cat);
    }

    return <div style={{"maxWidth": "768px", "margin": "0 auto", "padding": "24px"}}>
        <div style={{"display": "flex", "justifyContent": "space-between",
                     "alignItems": "center", "marginBottom": "24px"}}>
            <h1 style={{"fontSize": "28px", "fontWeight": "700"}}>Blog</h1>
            <button onClick={toggle_form}
                    style={{"padding": "8px 16px", "background": "#3b82f6", "color": "white",
                            "border": "none", "borderRadius": "8px", "cursor": "pointer"}}>
                {(showForm and "Cancel" or "New Post")}
            </button>
        </div>

        {showForm and (<PostForm onSubmit={postData["handleCreatePost"]} />)}

        <div style={{"display": "flex", "gap": "8px", "marginBottom": "16px"}}>
            {[
                <button key={cat} onClick={handle_category_click(cat)}
                        style={{
                            "padding": "6px 14px",
                            "borderRadius": "16px",
                            "border": "1px solid #d1d5db",
                            "background": (selectedCategory == cat and "#3b82f6" or "white"),
                            "color": (selectedCategory == cat and "white" or "#374151"),
                            "cursor": "pointer",
                            "fontSize": "13px"
                        }}>
                    {(cat or "All")}
                </button>
                for cat in categories
            ]}
        </div>

        {isLoading and (<p style={{"color": "#9ca3af"}}>Loading posts...</p>)}

        {len(posts) > 0 and (
            [<PostCard key={p["id"]} post={p} onDelete={postData["handleDeletePost"]} />
             for p in posts]
        )}

        {not isLoading and len(posts) == 0 and (
            <p style={{"color": "#9ca3af", "textAlign": "center", "padding": "40px"}}>
                No posts yet. Create the first one!
            </p>
        )}
    </div>;
}
```

### Page: pages/posts/[id].jac — Single Post (Dynamic Route)

```jac
"""Single post page with comments. Dynamic route: /posts/:id"""

cl import from "@jac/runtime" { useParams, Link }
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
        if result.success {
            post = result.post;
        } else {
            error = result.error or "Post not found";
        }
        isLoading = False;
    }

    if isLoading {
        return <p style={{"padding": "40px", "textAlign": "center", "color": "#9ca3af"}}>
            Loading...
        </p>;
    }

    if error {
        return <div style={{"padding": "40px", "textAlign": "center"}}>
            <p style={{"color": "#ef4444"}}>{error}</p>
            <Link to="/" style={{"color": "#3b82f6"}}>Back to posts</Link>
        </div>;
    }

    return <div style={{"maxWidth": "768px", "margin": "0 auto", "padding": "24px"}}>
        <Link to="/" style={{"color": "#3b82f6", "fontSize": "14px"}}>Back to posts</Link>
        <h1 style={{"fontSize": "32px", "fontWeight": "700", "marginTop": "16px"}}>
            {post["title"] or ""}
        </h1>
        {post["category"] and (
            <span style={{"padding": "4px 12px", "borderRadius": "16px",
                          "background": "#eff6ff", "color": "#3b82f6", "fontSize": "12px"}}>
                {post["category"]}
            </span>
        )}
        <div style={{"color": "#374151", "lineHeight": "1.8", "marginTop": "20px",
                     "whiteSpace": "pre-wrap"}}>
            {post["body"] or ""}
        </div>

        <CommentList postId={postId} />
    </div>;
}
```

---

## Example 3: Advanced — AI Agent with LLM Routing (Optional)
