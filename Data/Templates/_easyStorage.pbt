Assets {
  Id: 2805963157639982729
  Name: "@easyStorage"
  PlatformAssetType: 5
  TemplateAsset {
    ObjectBlock {
      RootId: 3454049609351584052
      Objects {
        Id: 3454049609351584052
        Name: "@easyStorage"
        Transform {
          Scale {
            X: 1
            Y: 1
            Z: 1
          }
        }
        ParentId: 4781671109827199097
        ChildIds: 17902948058519089468
        ChildIds: 713008881287934061
        UnregisteredParameters {
          Overrides {
            Name: "cs:STORAGE_VERSION"
            Int: 1
          }
          Overrides {
            Name: "cs:SHARED_STORAGE_VERSION"
            Int: 1
          }
          Overrides {
            Name: "cs:SHARED_STORAGE_KEY"
            NetReference {
              Type {
                Value: "mc:enetreferencetype:unknown"
              }
            }
          }
          Overrides {
            Name: "cs:SHARED_STORAGE_KEY:tooltip"
            String: "[Optional] Shared Storage Net Reference"
          }
          Overrides {
            Name: "cs:SHARED_STORAGE_KEY:category"
            String: "easyStorage_API"
          }
          Overrides {
            Name: "cs:STORAGE_VERSION:tooltip"
            String: "Current version of regular Storage data"
          }
          Overrides {
            Name: "cs:STORAGE_VERSION:category"
            String: "easyStorage_API"
          }
          Overrides {
            Name: "cs:SHARED_STORAGE_VERSION:tooltip"
            String: "[Optional] Current version of Shared Storage data."
          }
          Overrides {
            Name: "cs:SHARED_STORAGE_VERSION:category"
            String: "easyStorage_API"
          }
        }
        Collidable_v2 {
          Value: "mc:ecollisionsetting:inheritfromparent"
        }
        Visible_v2 {
          Value: "mc:evisibilitysetting:inheritfromparent"
        }
        CameraCollidable {
          Value: "mc:ecollisionsetting:inheritfromparent"
        }
        EditorIndicatorVisibility {
          Value: "mc:eindicatorvisibility:visiblewhenselected"
        }
        Folder {
          IsFilePartition: true
          FilePartitionName: "_easyStorage"
        }
      }
      Objects {
        Id: 17902948058519089468
        Name: "Modules"
        Transform {
          Location {
          }
          Rotation {
          }
          Scale {
            X: 1
            Y: 1
            Z: 1
          }
        }
        ParentId: 3454049609351584052
        ChildIds: 2986038103115172940
        ChildIds: 6736355531561656281
        UnregisteredParameters {
          Overrides {
            Name: "cs:easyStorageAPI"
            AssetReference {
              Id: 9898829530473888574
            }
          }
          Overrides {
            Name: "cs:BitArray"
            AssetReference {
              Id: 16087391583451673026
            }
          }
          Overrides {
            Name: "cs:Enum"
            AssetReference {
              Id: 10876574309383257670
            }
          }
          Overrides {
            Name: "cs:MessagePack"
            AssetReference {
              Id: 7103355485084642100
            }
          }
          Overrides {
            Name: "cs:QuickBase64"
            AssetReference {
              Id: 7645259355759957035
            }
          }
          Overrides {
            Name: "cs:LibLZW"
            AssetReference {
              Id: 225378120198817764
            }
          }
        }
        Collidable_v2 {
          Value: "mc:ecollisionsetting:inheritfromparent"
        }
        Visible_v2 {
          Value: "mc:evisibilitysetting:inheritfromparent"
        }
        CameraCollidable {
          Value: "mc:ecollisionsetting:inheritfromparent"
        }
        EditorIndicatorVisibility {
          Value: "mc:eindicatorvisibility:visiblewhenselected"
        }
        Folder {
          IsFilePartition: true
          FilePartitionName: "Modules"
        }
      }
      Objects {
        Id: 2986038103115172940
        Name: "DefaultContext"
        Transform {
          Location {
          }
          Rotation {
          }
          Scale {
            X: 1
            Y: 1
            Z: 1
          }
        }
        ParentId: 17902948058519089468
        ChildIds: 4765886392145235493
        Collidable_v2 {
          Value: "mc:ecollisionsetting:inheritfromparent"
        }
        Visible_v2 {
          Value: "mc:evisibilitysetting:inheritfromparent"
        }
        CameraCollidable {
          Value: "mc:ecollisionsetting:inheritfromparent"
        }
        EditorIndicatorVisibility {
          Value: "mc:eindicatorvisibility:visiblewhenselected"
        }
        Folder {
          IsFilePartition: true
          FilePartitionName: "DefaultContext"
        }
      }
      Objects {
        Id: 4765886392145235493
        Name: "InitModules"
        Transform {
          Location {
          }
          Rotation {
          }
          Scale {
            X: 1
            Y: 1
            Z: 1
          }
        }
        ParentId: 2986038103115172940
        Collidable_v2 {
          Value: "mc:ecollisionsetting:inheritfromparent"
        }
        Visible_v2 {
          Value: "mc:evisibilitysetting:inheritfromparent"
        }
        CameraCollidable {
          Value: "mc:ecollisionsetting:inheritfromparent"
        }
        EditorIndicatorVisibility {
          Value: "mc:eindicatorvisibility:visiblewhenselected"
        }
        Script {
          ScriptAsset {
            Id: 10904663549924109574
          }
        }
      }
      Objects {
        Id: 6736355531561656281
        Name: "ClientContext"
        Transform {
          Location {
          }
          Rotation {
          }
          Scale {
            X: 1
            Y: 1
            Z: 1
          }
        }
        ParentId: 17902948058519089468
        ChildIds: 4363771084980292245
        Collidable_v2 {
          Value: "mc:ecollisionsetting:forceoff"
        }
        Visible_v2 {
          Value: "mc:evisibilitysetting:inheritfromparent"
        }
        CameraCollidable {
          Value: "mc:ecollisionsetting:forceoff"
        }
        EditorIndicatorVisibility {
          Value: "mc:eindicatorvisibility:visiblewhenselected"
        }
        NetworkContext {
        }
      }
      Objects {
        Id: 4363771084980292245
        Name: "InitModules"
        Transform {
          Location {
          }
          Rotation {
          }
          Scale {
            X: 1
            Y: 1
            Z: 1
          }
        }
        ParentId: 6736355531561656281
        Collidable_v2 {
          Value: "mc:ecollisionsetting:inheritfromparent"
        }
        Visible_v2 {
          Value: "mc:evisibilitysetting:inheritfromparent"
        }
        CameraCollidable {
          Value: "mc:ecollisionsetting:inheritfromparent"
        }
        EditorIndicatorVisibility {
          Value: "mc:eindicatorvisibility:visiblewhenselected"
        }
        Script {
          ScriptAsset {
            Id: 10904663549924109574
          }
        }
      }
      Objects {
        Id: 713008881287934061
        Name: "easyStorage_README"
        Transform {
          Location {
          }
          Rotation {
          }
          Scale {
            X: 1
            Y: 1
            Z: 1
          }
        }
        ParentId: 3454049609351584052
        UnregisteredParameters {
          Overrides {
            Name: "cs:DataExample"
            AssetReference {
              Id: 6526640698689085722
            }
          }
        }
        Collidable_v2 {
          Value: "mc:ecollisionsetting:inheritfromparent"
        }
        Visible_v2 {
          Value: "mc:evisibilitysetting:inheritfromparent"
        }
        CameraCollidable {
          Value: "mc:ecollisionsetting:inheritfromparent"
        }
        EditorIndicatorVisibility {
          Value: "mc:eindicatorvisibility:visiblewhenselected"
        }
        Script {
          ScriptAsset {
            Id: 4002058138349424369
          }
        }
      }
    }
    PrimaryAssetId {
      AssetType: "None"
      AssetId: "None"
    }
  }
  SerializationVersion: 101
}
