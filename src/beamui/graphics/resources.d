/**
This module contains resource management.

When your application uses custom resources, you can embed resources into executable and/or specify external resource directory(s).

To embed resources, put them into views/res directory, and create file views/resources.list with list of all files to embed.

Use following code to embed resources:

---
/// Entry point for beamui-based application
extern (C) int UIAppMain(string[] args)
{
    // embed non-standard resources listed in views/resources.list into executable
    resourceList.embed!"resources.list";
    ...
}
---

Resource list resources.list file may look similar to following:

---
res/i18n/en.ini
res/i18n/ru.ini
res/mdpi/cr3_logo.png
res/mdpi/document-open.png
res/mdpi/document-properties.png
res/mdpi/document-save.png
res/mdpi/edit-copy.png
res/mdpi/edit-paste.png
res/mdpi/edit-undo.png
res/mdpi/tx_fabric.jpg
res/theme_custom1.xml
---

As well you can specify list of external directories to get resources from.

---
/// Entry point for beamui-based application
extern (C) int UIAppMain(string[] args)
{
    // resource directory search paths
    string[] resourceDirs = [
        appendPath(exePath, "../../../res/"),   // for Visual D and DUB builds
        appendPath(exePath, "../../../res/mdpi/"),   // for Visual D and DUB builds
        appendPath(exePath, "../../../../res/"),// for Mono-D builds
        appendPath(exePath, "../../../../res/mdpi/"),// for Mono-D builds
        appendPath(exePath, "res/"), // when res dir is located at the same directory as executable
        appendPath(exePath, "../res/"), // when res dir is located at project directory
        appendPath(exePath, "../../res/"), // when res dir is located at the same directory as executable
        appendPath(exePath, "res/mdpi/"), // when res dir is located at the same directory as executable
        appendPath(exePath, "../res/mdpi/"), // when res dir is located at project directory
        appendPath(exePath, "../../res/mdpi/") // when res dir is located at the same directory as executable
    ];
    // setup resource directories - will use only existing directories
    platform.resourceDirs = resourceDirs;
    ...
}
---

When same file exists in both embedded and external resources, one from external resource directory will be used -
it is useful for developing and testing of resources.

Synopsis:
---
import beamui.graphics.resources;

// embed non-standard resources listed in views/resources.list into executable
resourceList.embed!"resources.list";
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.graphics.resources;

import std.file;
import std.path;
import std.string;
import beamui.core.config;
import beamui.core.logger;
import beamui.core.types;

// TODO: platform-specific dir separator or UNIX slash?

__gshared ResourceList resourceList;

/// Filename prefix for embedded resources
immutable string EMBEDDED_RESOURCE_PREFIX = "@embedded@" ~ dirSeparator;

/// Resource list contains embedded resources and paths to external resource directories
struct ResourceList
{
    private EmbeddedResource[] embedded;
    private string[] _resourceDirs;
    private string[string] idToPath;

    /// Embed all resources from list
    void embed(string listFilename)()
    {
        static if (BACKEND_CONSOLE)
        {
            embedded ~= embedResources!(splitLines(import("console_" ~ listFilename)))();
        }
        else
        {
            embedded ~= embedResources!(splitLines(import(listFilename)))();
        }
    }

    /// Get resource directory paths
    @property string[] resourceDirs()
    {
        return _resourceDirs;
    }
    /// Set resource directory paths as variable number of parameters
    void setResourceDirs(string[] paths...)
    {
        resourceDirs(paths);
    }
    /// Set resource directory paths array (only existing dirs will be added)
    @property void resourceDirs(string[] paths)
    {
        string[] existingPaths;
        foreach (path; paths)
        {
            if (exists(path) && isDir(path))
            {
                existingPaths ~= path;
                Log.d("ResourceList: adding path ", path);
            }
            else
            {
                Log.d("ResourceList: path ", path, " does not exist.");
            }
        }
        _resourceDirs = existingPaths;
        clear();
    }

    void clear()
    {
        destroy(idToPath);
    }

    /**
    Get resource full pathname:
        * if provided path - by path relative to embedded files location or resource dirs
        * if provided extension - with extension
        * if nothing of those two - by base name
    Note: if there are two files with the same name, last path of the last file is returned.
    Null if not found.
    */
    string getPathByID(string id)
    {
        if (id.startsWith("#") || id.startsWith("{"))
            return id; // it's not a file name
        if (auto p = id in idToPath)
            return *p;

        import std.algorithm : any;

        bool searchWithDir = any!isDirSeparator(id);
        bool searchWithExt = extension(id) !is null;

        string tmp;
        string normID = buildNormalizedPath(id);

        // search in embedded
        // search backwards to allow overriding standard resources (which are added first)
        // double strip is needed for .9.png (is there a better solution?)
        foreach_reverse (ref r; embedded)
        {
            tmp = r.filename;
            if (!searchWithDir)
                tmp = baseName(tmp);
            if (!searchWithExt)
                tmp = stripExtension(stripExtension(tmp));
            if (tmp == normID)
            {
                // found
                string fn = EMBEDDED_RESOURCE_PREFIX ~ r.filename;
                idToPath[id] = fn;
                return fn;
            }
        }
        // search in external
        foreach (path; _resourceDirs)
        {
            foreach (fn; dirEntries(path, SpanMode.breadth))
            {
                tmp = fn;
                if (!searchWithDir)
                    tmp = baseName(tmp);
                if (!searchWithExt)
                    tmp = stripExtension(stripExtension(tmp));
                if (tmp == normID)
                {
                    // found
                    idToPath[id] = fn;
                    return fn;
                }
            }
        }
        Log.w("Resource ", id, " is not found");
        return null;
    }

    /**
    Get embedded resource by its full filename (without prefix).

    Null if not found.
    See `getPathByID` to get full filename.
    */
    EmbeddedResource* getEmbedded(string filename)
    {
        foreach_reverse (ref r; embedded)
        {
            if (filename == r.filename)
                return &r;
        }
        return null;
    }

    /// Print resource list stats
    debug void printStats()
    {
        foreach (r; embedded)
        {
            Log.d("EmbeddedResource: ", r.filename);
        }
        Log.d("Resource dirs: ", _resourceDirs);
    }
}

/**
    Load embedded resource or arbitrary file as a byte array.

    Name of embedded resource should start with `@embedded@/` prefix.
    Name of external file is a usual path.
*/
immutable(ubyte[]) loadResourceBytes(string filename)
{
    if (filename.startsWith(EMBEDDED_RESOURCE_PREFIX))
    {
        auto embedded = resourceList.getEmbedded(filename[EMBEDDED_RESOURCE_PREFIX.length .. $]);
        return embedded ? embedded.data : null;
    }
    else
    {
        try
        {
            return cast(immutable ubyte[])std.file.read(filename);
        }
        catch (Exception e)
        {
            Log.e("Exception while loading resource file ", filename);
            return null;
        }
    }
}

struct EmbeddedResource
{
    immutable string filename;
    immutable ubyte[] data;
}

/// Embed all resources from list
private EmbeddedResource[] embedResources(string[] resourceNames)()
{
    EmbeddedResource[] list;
    static foreach (r; resourceNames)
        list ~= embedResource!r;
    return list;
}

private EmbeddedResource[] embedResource(string resourceName)()
{
    static if (resourceName.startsWith("#")) // comment
    {
        return [];
    }
    else
    {
        // WARNING: some compilers may disallow import file by full path.
        // in this case `getPathByID` will not adress embedded resources by path
        version (USE_BASE_PATH_FOR_RESOURCES)
        {
            immutable string name = baseName(resourceName);
        }
        else
        {
            immutable string name = resourceName;
        }
        static if (name.length > 0)
        {
            auto data = cast(immutable ubyte[])import(name);
            static if (data.length > 0)
                return [EmbeddedResource(buildNormalizedPath(name), data)];
            else
                return [];
        }
        else
            return [];
    }
}
