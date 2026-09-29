using Assimp.Maui;

namespace Assimp.MAUI.Sample;

public sealed class SceneRenderer : IDrawable
{
    private readonly List<Triangle> _triangles = [];
    private readonly Dictionary<uint, MaterialStyle> _materials = [];
    private float _rotationX = -0.35f;
    private float _rotationY = 0.55f;
    private float _scale = 1f;
    private IImage? _texture;
    private string? _textureName;
    private bool _wireframe;
    private bool _lighting = true;
    private bool _useTexture = true;

    public int MeshCount { get; private set; }
    public int VertexCount { get; private set; }
    public int FaceCount { get; private set; }
    public int MaterialCount { get; private set; }
    public int TextureCount { get; private set; }

    public void SetScene(Scene? scene)
    {
        _triangles.Clear();
        _materials.Clear();
        MeshCount = 0;
        VertexCount = 0;
        FaceCount = 0;
        MaterialCount = scene is null ? 0 : checked((int)scene.NumMaterials);
        TextureCount = scene is null ? 0 : checked((int)scene.NumTextures);

        if (scene is null || !scene.HasMeshes())
            return;

        MeshCount = checked((int)scene.NumMeshes);

        for (uint meshIndex = 0; meshIndex < scene.NumMeshes; meshIndex++)
        {
            using var mesh = scene.GetMesh(meshIndex);
            if (mesh is null || !mesh.HasPositions() || !mesh.HasFaces())
                continue;

            VertexCount += checked((int)mesh.NumVertices);
            FaceCount += checked((int)mesh.NumFaces);

            var materialIndex = mesh.GetMaterialIndex();
            if (!_materials.ContainsKey(materialIndex))
                _materials[materialIndex] = CreateMaterial(materialIndex);

            ReadMesh(mesh, materialIndex);
        }

        Normalize();
    }

    public void SetMaterial(uint materialIndex, Color color, float roughness)
    {
        _materials[materialIndex] = new MaterialStyle(color, Math.Clamp(roughness, 0f, 1f));
    }

    public void SetTexture(IImage? texture, string? name)
    {
        _texture?.Dispose();
        _texture = texture;
        _textureName = name;
    }

    public string TextureDescription =>
        _texture is null ? "No texture" : $"Texture: {_textureName ?? "loaded"}";

    public void ToggleTexture() => _useTexture = !_useTexture;
    public void ToggleLighting() => _lighting = !_lighting;
    public void ToggleWireframe() => _wireframe = !_wireframe;

    public void ResetCamera()
    {
        _rotationX = -0.35f;
        _rotationY = 0.55f;
        _scale = 1f;
    }

    public void Rotate(float deltaX, float deltaY)
    {
        _rotationY += deltaX * 0.01f;
        _rotationX = Math.Clamp(_rotationX + deltaY * 0.01f, -1.5f, 1.5f);
    }

    public void Zoom(float delta) =>
        _scale = Math.Clamp(_scale * (1f + delta), 0.1f, 10f);

    public IReadOnlyList<ShaderMesh> ExportShaderMeshes()
    {
        return _triangles
            .GroupBy(t => t.MeshIndex)
            .Select(group => new ShaderMesh(
                group.Key,
                group.SelectMany(t => new[] { t.A.Position, t.B.Position, t.C.Position })
                    .SelectMany(p => new[] { p.X, p.Y, p.Z })
                    .ToArray(),
                group.SelectMany(t => new[] { t.A.UV, t.B.UV, t.C.UV })
                    .SelectMany(p => new[] { p.X, p.Y })
                    .ToArray()))
            .ToArray();
    }

    public void Draw(ICanvas canvas, RectF dirtyRect)
    {
        canvas.FillColor = new Color(0.035f, 0.045f, 0.06f);
        canvas.FillRectangle(dirtyRect);

        if (_triangles.Count == 0)
        {
            canvas.FontColor = Colors.White;
            canvas.FontSize = 16;
            canvas.DrawString("Open a 3D asset to start the Assimp.MAUI demonstration.",
                dirtyRect.Center.X, dirtyRect.Center.Y, HorizontalAlignment.Center);
            return;
        }

        var projected = _triangles
            .Select(triangle =>
            {
                var a = Project(triangle.A.Position, dirtyRect);
                var b = Project(triangle.B.Position, dirtyRect);
                var c = Project(triangle.C.Position, dirtyRect);
                return new ProjectedTriangle(triangle, a, b, c, (a.Z + b.Z + c.Z) / 3f);
            })
            .OrderBy(t => t.Depth);

        foreach (var projectedTriangle in projected)
        {
            var path = new PathF();
            path.MoveTo(projectedTriangle.A.X, projectedTriangle.A.Y);
            path.LineTo(projectedTriangle.B.X, projectedTriangle.B.Y);
            path.LineTo(projectedTriangle.C.X, projectedTriangle.C.Y);
            path.Close();

            var color = _materials.TryGetValue(projectedTriangle.Source.MaterialIndex, out var material)
                ? material.Color
                : Colors.SlateGray;

            if (_lighting)
                color = ApplyLighting(color, projectedTriangle.Source);

            if (_texture is not null && _useTexture)
            {
                canvas.SaveState();
                canvas.ClipPath(path);
                canvas.DrawImage(_texture, projectedTriangle.Bounds);
                canvas.RestoreState();
            }
            else
            {
                canvas.FillColor = color;
                canvas.FillPath(path);
            }

            if (_wireframe)
            {
                canvas.StrokeColor = Colors.White.WithAlpha(0.55f);
                canvas.StrokeSize = 0.75f;
                canvas.DrawPath(path);
            }
        }

        canvas.FontColor = Colors.White.WithAlpha(0.65f);
        canvas.FontSize = 12;
        canvas.DrawString(
            $"{MeshCount} mesh(es)  •  {MaterialCount} material(s)  •  {TextureCount} embedded texture(s)",
            12, 12, HorizontalAlignment.Left);
    }

    private void ReadMesh(Mesh mesh, uint materialIndex)
    {
        for (uint faceIndex = 0; faceIndex < mesh.NumFaces; faceIndex++)
        {
            var count = mesh.GetFaceIndexCount(faceIndex);
            if (count < 3)
                continue;

            var first = mesh.GetFaceIndex(faceIndex, 0);
            for (uint i = 1; i + 1 < count; i++)
            {
                var second = mesh.GetFaceIndex(faceIndex, i);
                var third = mesh.GetFaceIndex(faceIndex, i + 1);
                _triangles.Add(new Triangle(
                    ReadVertex(mesh, first),
                    ReadVertex(mesh, second),
                    ReadVertex(mesh, third),
                    materialIndex,
                    MeshCount - 1));
            }
        }
    }

    private static Vertex ReadVertex(Mesh mesh, uint index)
    {
        var position = new Point3D(
            mesh.GetVertexComponent(index, 0),
            mesh.GetVertexComponent(index, 1),
            mesh.GetVertexComponent(index, 2));

        var uv = mesh.HasTextureCoords(0)
            ? new Point2D(
                mesh.GetTextureCoordinateComponent(0, index, 0),
                1f - mesh.GetTextureCoordinateComponent(0, index, 1))
            : new Point2D(0.5f, 0.5f);

        return new Vertex(position, uv);
    }

    private void Normalize()
    {
        if (_triangles.Count == 0)
            return;

        var points = _triangles.SelectMany(t => new[] { t.A.Position, t.B.Position, t.C.Position }).ToArray();
        var minX = points.Min(p => p.X);
        var maxX = points.Max(p => p.X);
        var minY = points.Min(p => p.Y);
        var maxY = points.Max(p => p.Y);
        var minZ = points.Min(p => p.Z);
        var maxZ = points.Max(p => p.Z);
        var center = new Point3D(
            (minX + maxX) / 2f,
            (minY + maxY) / 2f,
            (minZ + maxZ) / 2f);

        var size = Math.Max(maxX - minX, Math.Max(maxY - minY, maxZ - minZ));
        var factor = size > 0 ? 2f / size : 1f;

        for (var i = 0; i < _triangles.Count; i++)
        {
            var t = _triangles[i];
            _triangles[i] = t with
            {
                A = t.A with { Position = Center(t.A.Position, center, factor) },
                B = t.B with { Position = Center(t.B.Position, center, factor) },
                C = t.C with { Position = Center(t.C.Position, center, factor) }
            };
        }
    }

    private Point3D Project(Point3D point, RectF bounds)
    {
        var cosY = MathF.Cos(_rotationY);
        var sinY = MathF.Sin(_rotationY);
        var cosX = MathF.Cos(_rotationX);
        var sinX = MathF.Sin(_rotationX);
        var x = point.X * cosY - point.Z * sinY;
        var z = point.X * sinY + point.Z * cosY;
        var y = point.Y * cosX - z * sinX;
        z = point.Y * sinX + z * cosX;
        var perspective = 2.8f / (3.4f - z);
        var size = MathF.Min(bounds.Width, bounds.Height) * 0.4f * _scale;

        return new Point3D(
            bounds.Center.X + x * perspective * size,
            bounds.Center.Y - y * perspective * size,
            z);
    }

    private static Color ApplyLighting(Color color, Triangle triangle)
    {
        var ab = Subtract(triangle.B.Position, triangle.A.Position);
        var ac = Subtract(triangle.C.Position, triangle.A.Position);
        var normal = Normalize(Cross(ab, ac));
        var light = Normalize(new Point3D(-0.45f, 0.75f, 0.65f));
        var diffuse = 0.35f + Math.Max(0f, Dot(normal, light)) * 0.65f;
        return new Color(color.Red * diffuse, color.Green * diffuse, color.Blue * diffuse, color.Alpha);
    }

    private static MaterialStyle CreateMaterial(uint index)
    {
        var palette = new[]
        {
            Colors.CornflowerBlue, Colors.Orange, Colors.MediumSeaGreen,
            Colors.MediumPurple, Colors.Goldenrod, Colors.IndianRed
        };
        return new MaterialStyle(palette[index % (uint)palette.Length], 0.45f);
    }

    private static Point3D Center(Point3D point, Point3D center, float factor) =>
        new((point.X - center.X) * factor, (point.Y - center.Y) * factor, (point.Z - center.Z) * factor);

    private static Point3D Subtract(Point3D a, Point3D b) =>
        new(a.X - b.X, a.Y - b.Y, a.Z - b.Z);

    private static Point3D Cross(Point3D a, Point3D b) =>
        new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X);

    private static float Dot(Point3D a, Point3D b) => a.X * b.X + a.Y * b.Y + a.Z * b.Z;

    private static Point3D Normalize(Point3D value)
    {
        var length = MathF.Sqrt(Dot(value, value));
        return length <= 0.0001f ? new Point3D(0, 0, 1) : new Point3D(value.X / length, value.Y / length, value.Z / length);
    }

    private readonly record struct MaterialStyle(Color Color, float Roughness);
    private readonly record struct Vertex(Point3D Position, Point2D UV);
    private readonly record struct Point2D(float X, float Y);
    private readonly record struct Point3D(float X, float Y, float Z);
    private readonly record struct Triangle(Point3D A, Point3D B, Point3D C, uint MaterialIndex, int MeshIndex)
    {
        public Point2D UV_A => default;
        public Point2D UV_B => default;
        public Point2D UV_C => default;
        public RectF Bounds => new(
            Math.Min(Math.Min(A.X, B.X), C.X),
            Math.Min(Math.Min(A.Y, B.Y), C.Y),
            Math.Max(Math.Max(A.X, B.X), C.X),
            Math.Max(Math.Max(A.Y, B.Y), C.Y));
    }

    private readonly record struct ProjectedTriangle(Triangle Source, Point3D A, Point3D B, Point3D C, float Depth);
    public sealed record ShaderMesh(int MeshIndex, float[] Positions, float[] UVs);
}
