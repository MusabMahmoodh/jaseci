# Asset Serving in Jac

This guide covers all approaches for serving static assets (images, fonts, videos, etc.) in Jac web applications. Each approach is demonstrated with complete, working examples.

## Quick Navigation

### ✅ Available Examples

| Asset Pattern | Documentation | Example Location |
|---------------|--------------|------------------|
| [**Static Path Serving**](./static-path.md) | Direct `/static/` path references | [`examples/asset-serving/image-asset/`](../../../examples/asset-serving/image-asset/) |
| [**Import Alias**](./import-alias.md) | Using `@jac-client/assets` alias | [`examples/asset-serving/import-alias/`](../../../examples/asset-serving/import-alias/) |
| [**Relative Imports**](./relative-imports.md) | Relative path imports | [`examples/asset-serving/relative-imports/`](../../../examples/asset-serving/relative-imports/) |
| [**Vite-Bundled Assets**](./vite-bundled.md) | Assets processed by Vite | [`examples/asset-serving/vite-bundled-assets/`](../../../examples/asset-serving/vite-bundled-assets/) |

## Asset Serving Approaches Overview

### Static Path Serving
- **Direct Paths** — Reference assets via `/static/` URLs
  - Simple and straightforward
  - Works immediately without build configuration
  - Perfect for quick prototypes and simple projects

### Import-Based Serving
- **Import Alias** — Use `@jac-client/assets` alias for type-safe imports
  - Vite handles asset optimization
  - Automatic hash generation for cache busting
  - Better for production applications

- **Relative Imports** — Import assets using relative paths
  - Familiar import syntax
  - Works with Vite's asset handling
  - Good for component-scoped assets

### Vite-Bundled Assets
- **Processed Assets** — Assets processed through Vite build pipeline
  - Automatic optimization and compression
  - Hash-based filenames for cache invalidation
  - Best performance and caching strategy

## Supported Asset Types

Jac supports serving a wide variety of static assets:

### Images
- **Raster Images**: `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.ico`
- **Vector Images**: `.svg`
- **Modern Formats**: `.avif`, `.heic` (browser-dependent)

### Fonts
- **Web Fonts**: `.woff`, `.woff2`, `.ttf`, `.otf`, `.eot`
- **Font Files**: Automatically served with correct MIME types

### Media Files
- **Video**: `.mp4`, `.webm`, `.ogg`, `.mov`
- **Audio**: `.mp3`, `.wav`, `.ogg`, `.m4a`

### Documents
- **PDFs**: `.pdf`
- **Other**: Any file type can be served as binary

## Asset Serving Methods

### Method 1: Static Path (Direct URL)

Reference assets directly using the `/static/` path:

```jac
<img src="/static/assets/burger.png" alt="Burger" />
```

**How it works:**
- Assets in `assets/` folder are served at `/static/assets/` path
- Assets in `dist/` folder are also accessible via `/static/`
- Server automatically detects file type and sets correct MIME type
- Simple and works immediately

**Best for:**
- Quick prototypes
- Simple applications
- Assets that don't need optimization

### Method 2: Import Alias

Import assets using the `@jac-client/assets` alias:

```jac
cl import from "@jac-client/assets/burger.png" { default as burgerImage }
<img src={burgerImage} />
```

**How it works:**
- Alias configured in `vite.config.js` points to `src/assets/`
- Assets from root `assets/` folder are copied to `src/assets/` during build
- Vite processes the import and generates optimized asset URLs
- Automatic hash generation for cache busting

**Best for:**
- Production applications
- Assets that benefit from optimization
- Type-safe asset references

### Method 3: Relative Imports

Import assets using relative paths:

```jac
cl import from "./assets/burger.png" { default as burgerImage }
<img src={burgerImage} />
```

**How it works:**
- Similar to import alias but uses relative paths
- Vite resolves and processes the import
- Works well for component-scoped assets

**Best for:**
- Component-specific assets
- Assets organized by feature/component
- Projects with modular structure

### Method 4: Vite-Bundled Assets

Assets processed through Vite's build pipeline:

```jac
cl import from "./images/hero.jpg" { default as heroImage }
```

**How it works:**
- Vite processes assets during build
- Generates optimized versions with hashed filenames
- Assets are bundled and served from `dist/` directory
- Automatic compression and optimization

**Best for:**
- Production builds
- Large applications
- Assets requiring optimization

## Choosing the Right Approach

### Decision Matrix

| Method | Setup Complexity | Build Time | Runtime Performance | Cache Strategy | Best For |
|--------|-----------------|------------|---------------------|----------------|----------|
| Static Path | Low | None | Good | Manual | Prototypes |
| Import Alias | Medium | Low | Excellent | Automatic | Production |
| Relative Import | Medium | Low | Excellent | Automatic | Components |
| Vite-Bundled | Medium | Medium | Excellent | Automatic | Large Apps |

### Quick Decision Guide

**Choose Static Path if:**
- Building a quick prototype
- Assets don't need optimization
- Want immediate results without build step
- Working with simple, small assets

**Choose Import Alias if:**
- Building a production application
- Want automatic cache busting
- Need asset optimization
- Prefer type-safe imports

**Choose Relative Imports if:**
- Organizing assets by component/feature
- Want component-scoped assets
- Prefer relative path semantics
- Building modular applications

**Choose Vite-Bundled if:**
- Building large applications
- Need maximum performance
- Want automatic asset optimization
- Require hash-based cache invalidation

## Asset Organization

### Recommended Structure

```
project/
├── assets/              # Root assets folder (served via /static/)
│   ├── images/
│   │   ├── logo.png
│   │   └── hero.jpg
│   ├── fonts/
│   │   └── custom.woff2
│   └── videos/
│       └── intro.mp4
├── src/
│   └── assets/         # Assets for import alias (@jac-client/assets)
│       └── components/
│           └── button-icon.svg
└── dist/               # Vite output (auto-generated)
    └── assets/
        └── [hashed-files]
```

### Best Practices

1. **Organization**: Group assets by type (images, fonts, videos)
2. **Naming**: Use descriptive, consistent file names
3. **Optimization**: Optimize images before adding to project
4. **Size**: Keep assets reasonably sized for web delivery
5. **Format**: Use modern formats (WebP, WOFF2) when possible

## Import Syntax

### Static Path (No Import)

```jac
# Direct usage in JSX
<img src="/static/assets/logo.png" alt="Logo" />
<link rel="stylesheet" href="/static/styles.css" />
```

### Import Alias

```jac
# Images
cl import from "@jac-client/assets/logo.png" { default as logo }
<img src={logo} />

# Multiple assets
cl import from "@jac-client/assets/hero.jpg" { default as heroImage }
cl import from "@jac-client/assets/icon.svg" { default as icon }
```

### Relative Imports

```jac
# Component-scoped assets
cl import from "./assets/button-icon.svg" { default as buttonIcon }
cl import from "../shared/images/logo.png" { default as sharedLogo }
```

### CSS Background Images

```jac
# In CSS files
.hero {
  background-image: url('/static/assets/hero.jpg');
}

# Or using imports in JSX
let heroImage = "/static/assets/hero.jpg";
<div style={{backgroundImage: `url(${heroImage})`}} />
```

## Server Configuration

### Asset Serving Locations

The server automatically checks multiple locations when serving `/static/*` requests:

1. **`dist/` directory** — Vite-bundled assets (highest priority)
2. **`assets/` directory** — User-provided static assets

### Supported File Types

The server automatically detects and serves:
- **Images**: PNG, JPG, JPEG, GIF, WebP, SVG, ICO
- **Fonts**: WOFF, WOFF2, TTF, OTF, EOT
- **Media**: MP4, WebM, MP3, WAV
- **Documents**: PDF
- **CSS**: CSS, SCSS, SASS, LESS
- **Other**: Any binary file type

### MIME Type Detection

The server automatically:
- Detects file type from extension
- Sets appropriate `Content-Type` header
- Handles binary files correctly
- Sets cache headers for optimal performance

## Running Examples

Each example is a complete, runnable project:

```bash
# Navigate to example directory
cd jac/examples/asset-serving/<example-name>

# Install dependencies
npm install

# Run the application
jac serve app.jac

# Open in browser
# http://localhost:8000/page/app
```

Available examples:
- `image-asset` - Static path serving
- `import-alias` - Import alias pattern
- `relative-imports` - Relative imports
- `vite-bundled-assets` - Vite-bundled assets

## Performance Considerations

### Asset Optimization

1. **Image Compression**: Use tools like ImageOptim or Squoosh
2. **Format Selection**: Prefer WebP for photos, SVG for icons
3. **Lazy Loading**: Use `loading="lazy"` for below-fold images
4. **Responsive Images**: Use `srcset` for different screen sizes

### Caching Strategy

- **Static Path**: Manual cache control via query parameters
- **Import Alias**: Automatic hash-based cache busting
- **Vite-Bundled**: Automatic hash in filename for cache invalidation

### Best Practices

1. **Optimize Before Adding**: Compress images before committing
2. **Use Appropriate Formats**: WebP for photos, SVG for icons
3. **Lazy Load**: Load images only when needed
4. **CDN Consideration**: Use CDN for production deployments
5. **Bundle Size**: Monitor total asset bundle size

## Troubleshooting

### Common Issues

**Asset not found (404)**
- Check file exists in `assets/` or `dist/` directory
- Verify path in code matches file location
- Ensure file extension matches

**Import not resolving**
- Verify `vite.config.js` has `@jac-client/assets` alias
- Check assets are copied to `src/assets/` during build
- Ensure import path matches alias configuration

**Wrong MIME type**
- Server auto-detects from file extension
- Verify file extension is correct
- Check file is not corrupted

**Assets not updating**
- Clear browser cache
- Check if using hash-based filenames (should auto-update)
- Verify build process completed successfully

## Resources

- [Import System Documentation](../imports.md)
- [Styling Documentation](../styling/intro.md)
- [Routing Documentation](../routing.md)
- [Complete Example Guide](../guide-example/intro.md)
- [Architecture Overview](../../jac-client/architecture.md)

## Contributing

When adding new asset serving examples:

1. Create a new directory in `examples/`
2. Include a complete working example
3. Add a README.md with setup instructions
4. Create a documentation file in `docs/asset-serving/`
5. Update this intro.md file
6. Follow the existing example structure

