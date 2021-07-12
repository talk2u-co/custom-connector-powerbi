﻿section WeniFluxos;

BaseUrl = "https://push-staging.push.al/api/v2/";

// BaseUrl = "https://new.push.al/api/v2/";

WeniFluxos.RootEntities = {
    "broadcasts.json",
    "channel_stats.json",
    "contacts.json",
    "flows.json",
    "flow_starts.json",
    "messages.json",
    "runs.json"
};

[DataSource.Kind="WeniFluxos", Publish="WeniFluxos.Publish"]
shared WeniFluxos.Contents = (token as text, optional after as datetime, optional before as datetime) => WeniFluxosNavTable(BaseUrl, token, after, before) as table;

WeniFluxos.GetData = (url as text, token as text, after as nullable datetime, before as nullable datetime) as table => GetAllPagesByNextLink(url, token, after, before);

WeniFluxosNavTable = (url as text, token as text, after as nullable datetime, before as nullable datetime) as table =>
    let
        entitiesAsTable = Table.FromList(WeniFluxos.RootEntities, Splitter.SplitByNothing()),
        rename = Table.RenameColumns(entitiesAsTable, {{"Column1", "Endpoint"}}),
        withEntity = Table.AddColumn(rename, "Name", each Text.BeforeDelimiter([Endpoint],".")),
        withData = Table.AddColumn(withEntity, "Data", each WeniFluxos.GetData(Uri.Combine(url, [Endpoint]), token, after, before), Uri.Type),
        withItemKind = Table.AddColumn(withData, "ItemKind", each "Table", type text),
        withItemName = Table.AddColumn(withItemKind, "ItemName", each "Table", type text),
        withIsLeaf = Table.AddColumn(withItemName, "IsLeaf", each true, type logical),
        withoutEndpoint = Table.RemoveColumns(withIsLeaf, "Endpoint"),
        navTable = Table.ToNavigationTable(withoutEndpoint, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        navTable;

Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;

Table.GenerateByPage = (getNextPage as function) as table =>
    let
        listOfPages = List.Generate(
            () => getNextPage(null),     
            (lastPage) => lastPage <> null,
            (lastPage) => getNextPage(lastPage)
        ),
        tableOfPages = Table.FromList(listOfPages, Splitter.SplitByNothing(), {"Column1"}),
        firstRow = tableOfPages{0}?
    in
        if (firstRow = null) then
            Table.FromRows({})
        else        
            Value.ReplaceType(
                Table.ExpandTableColumn(tableOfPages, "Column1", Table.ColumnNames(firstRow[Column1])),
                Value.Type(firstRow[Column1])
            );

GetAllPagesByNextLink = (url as text, token as text, after as nullable datetime, before as nullable datetime) as table =>
    Table.GenerateByPage((previous) => 
        let
            nextLink = if (previous = null) then url else Value.Metadata(previous)[NextLink]?,
            afterParam = if (previous = null) then after else null,  //prevent duplicate param in next link
            beforeParam = if (previous = null) then before else null,//\\ same
            page = if (nextLink <> null) then GetPage(nextLink, token, afterParam, beforeParam) else null
        in
            page
    );

GetPage = (url as text, token as text, after as nullable datetime, before as nullable datetime) as table =>
    let
        options = [
            Headers = [
                #"Accept" = "application/json",
                #"Authorization" = "Token " & token
            ]
        ],
        afterQ = if (after = null) then [] else [after = DateTime.ToText(after, "yyyy-MM-ddThh:mm:ss")],
        beforeQ = if (before = null) then [] else [before = DateTime.ToText(before, "yyyy-MM-ddThh:mm:ss")],
        query = Record.Combine({afterQ, beforeQ}),
        optionsWithQuery = Record.AddField(options, "Query", query), 
        response = Web.Contents(
            url, 
            optionsWithQuery
        ),
        body = Json.Document(response, 1252),
        nextLink = GetNextLink(body),
        data = Table.FromRecords(body[results])
    in
        data meta [NextLink = nextLink];

GetNextLink = (response) as nullable text => Record.FieldOrDefault(response, "next");

WeniFluxos = [
    Authentication = [
        Implicit = []
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

WeniFluxos.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { "Weni Fluxos API", "Weni Fluxos API" },
    LearnMoreUrl = BaseUrl,
    SourceImage = WeniFluxos.Icons,
    SourceTypeImage = WeniFluxos.Icons
];

WeniFluxos.Icons = [
    Icon16 = { Extension.Contents("WeniFluxos16.png"), Extension.Contents("WeniFluxos20.png"), Extension.Contents("WeniFluxos24.png"), Extension.Contents("WeniFluxos32.png") },
    Icon32 = { Extension.Contents("WeniFluxos32.png"), Extension.Contents("WeniFluxos40.png"), Extension.Contents("WeniFluxos48.png"), Extension.Contents("WeniFluxos64.png") }
];