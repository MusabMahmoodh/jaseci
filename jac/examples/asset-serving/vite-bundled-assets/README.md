# Vite-Bundled Assets Example

This example demonstrates how assets are processed through Vite's build pipeline for optimal performance.

## Features

- Assets processed through Vite build pipeline
- Automatic optimization and compression
- Hash-based filenames for cache busting
- Assets bundled into `dist/` directory
- Code splitting support

## Project Structure

```
vite-bundled-assets/
├── app.jac          # Main application file
├── assets/          # Static assets directory
│   └── burger.png   # Burger image
├── src/             # Source files (generated)
├── build/           # Build output (generated)
└── dist/            # Distribution output (generated)
    └── assets/      # Processed assets with hashes
```

## Running the Example

1. Make sure node modules are installed:
```bash
npm install
```

2. Run the Jac server:
```bash
jac serve app.jac
```

3. Open your browser and navigate to:
```
http://localhost:8000/page/app
```

## How It Works

### Build Process

1. **Compilation**: Jac code is compiled to JavaScript
2. **Asset Copying**: Assets from `assets/` are copied to `src/assets/`
3. **Babel Transpilation**: JavaScript is transpiled from `src/` to `build/`
4. **Vite Bundling**: Vite processes imports and bundles assets
5. **Optimization**: Assets are optimized and compressed
6. **Hash Generation**: Filenames include content hashes
7. **Output**: Bundled assets are written to `dist/`

### Import Syntax

```jac
cl import from "@jac-client/assets/burger.png" { default as burgerImage }
```

### Asset Processing

Vite automatically:
- **Optimizes images**: Compression and format conversion
- **Generates hashes**: Content-based filenames for cache busting
- **Bundles assets**: Groups related assets together
- **Code splits**: Separates large assets for lazy loading

### Output Structure

After build, assets in `dist/` have hashed filenames:
```
dist/
├── client.[hash].js
└── assets/
    └── burger.[hash].png
```

### Benefits

- **Performance**: Optimized assets load faster
- **Caching**: Hash-based filenames enable long-term caching
- **Compression**: Automatic image compression
- **Code Splitting**: Large assets can be lazy-loaded
- **Production Ready**: Optimized for production deployments

## Build Commands

```bash
# Development build
npm run compile

# Production build
npm run build

# Preview production build
npm run preview
```

## Best Practices

1. Use this method for production applications
2. Let Vite handle optimization automatically
3. Monitor bundle size for large assets
4. Use appropriate image formats (WebP, AVIF)
5. Consider lazy loading for below-fold images

## Asset Optimization Tips

1. **Image Formats**: Use WebP or AVIF for better compression
2. **Image Size**: Optimize images before adding to project
3. **Lazy Loading**: Use `loading="lazy"` for images below fold
4. **Responsive Images**: Use `srcset` for different screen sizes
5. **SVG Optimization**: Optimize SVG files before importing

Happy coding with Jac! 🍔
