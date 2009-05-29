-----------------------------------------------------------------------
--                           G N A T C O L L                         --
--                                                                   --
--                 Copyright (C) 2005-2009, AdaCore                  --
--                                                                   --
-- GPS is free  software;  you can redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this program; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with Ada.Strings.Hash;
with Ada.Strings.Unbounded;      use Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with GNAT.Strings;               use GNAT.Strings;

package body GNATCOLL.SQL_Impl is

   use Field_List, Table_Sets, Assignment_Lists;

   Comparison_Equal         : aliased constant String := "=";
   Comparison_Different     : aliased constant String := "<>";
   Comparison_Less          : aliased constant String := "<";
   Comparison_Less_Equal    : aliased constant String := "<=";
   Comparison_Greater       : aliased constant String := ">";
   Comparison_Greater_Equal : aliased constant String := ">=";

   procedure Assign
     (R     : out SQL_Assignment;
      Field : SQL_Field'Class;
      Value : GNAT.Strings.String_Access);
   --  Assign Value to Field (or set field to NULL if Value is null)

   --------------------------
   --  Named field data --
   --------------------------
   --  Instantiation of field_data for specific types of fields, created for
   --  instance via Expression, From_String, or operators on time. Such fields
   --  are still typed

   type Named_Field_Internal is new SQL_Field_Internal with record
      Table : Table_Names := No_Names;

      Value : GNAT.Strings.String_Access;
      --  The expression representing the field in SQL

      Operator : GNAT.Strings.String_Access;
      --  null unless we have an operator on several fields ("-" for instance)

      List     : SQL_Field_List;
   end record;
   type Named_Field_Internal_Access is access all Named_Field_Internal'Class;
   overriding procedure Free (Self : in out Named_Field_Internal);
   overriding function To_String
     (Self : Named_Field_Internal; Long : Boolean) return String;
   overriding procedure Append_Tables
     (Self : Named_Field_Internal; To : in out Table_Sets.Set);
   overriding procedure Append_If_Not_Aggregate
     (Self         : access Named_Field_Internal;
      To           : in out SQL_Field_List'Class;
      Is_Aggregate : in out Boolean);

   --------------
   -- Criteria --
   --------------

   type Comparison_Criteria is new SQL_Criteria_Data with record
      Op, Suffix : Cst_String_Access;
      Arg1, Arg2 : SQL_Field_Pointer;
   end record;
   overriding function To_String
     (Self : Comparison_Criteria; Long : Boolean := True) return String;
   overriding procedure Append_Tables
     (Self : Comparison_Criteria; To : in out Table_Sets.Set);
   overriding procedure Append_If_Not_Aggregate
     (Self         : Comparison_Criteria;
      To           : in out SQL_Field_List'Class;
      Is_Aggregate : in out Boolean);

   ----------------
   -- Data_Field --
   ----------------

   package body Data_Fields is
      overriding function To_String
        (Self : Field; Long : Boolean := True) return String is
      begin
         if Self.Data.Data /= null then
            return To_String (Self.Data.Data.all, Long);
         else
            return "";
         end if;
      end To_String;

      overriding procedure Append_Tables
        (Self : Field; To : in out Table_Sets.Set) is
      begin
         if Self.Data.Data /= null then
            Append_Tables (Self.Data.Data.all, To);
         end if;
      end Append_Tables;

      overriding procedure Append_If_Not_Aggregate
        (Self         : Field;
         To           : in out SQL_Field_List'Class;
         Is_Aggregate : in out Boolean)
      is
      begin
         if Self.Data.Data /= null then
            Append_If_Not_Aggregate (Self.Data.Data, To, Is_Aggregate);
         end if;
      end Append_If_Not_Aggregate;
   end Data_Fields;

   package Any_Fields is new Data_Fields (SQL_Field);

   ----------
   -- Hash --
   ----------

   function Hash (Self : Table_Names) return Ada.Containers.Hash_Type is
   begin
      if Self.Instance = null then
         return Ada.Strings.Hash (Self.Name.all);
      else
         return Ada.Strings.Hash (Self.Instance.all);
      end if;
   end Hash;

   ---------------
   -- To_String --
   ---------------

   overriding function To_String
     (Self : SQL_Field_List; Long : Boolean := True) return String
   is
      C      : Field_List.Cursor := First (Self.List);
      Result : Unbounded_String;
   begin
      if Has_Element (C) then
         Append (Result, To_String (Element (C), Long));
         Next (C);
      end if;

      while Has_Element (C) loop
         Append (Result, ", ");
         Append (Result, To_String (Element (C), Long));
         Next (C);
      end loop;
      return To_String (Result);
   end To_String;

   ---------------
   -- To_String --
   ---------------

   overriding function To_String
     (Self : SQL_Field; Long : Boolean := True) return String is
   begin
      if not Long then
         return Self.Name.all;
      elsif Self.Instance /= null then
         return Self.Instance.all & "." & Self.Name.all;

      elsif Self.Table /= null then
         return Self.Table.all & "." & Self.Name.all;

      else
         --  Self.Table could be null in the case of the Null_Field_*
         --  constants
         return Self.Name.all;
      end if;
   end To_String;

   ----------
   -- Free --
   ----------

   procedure Free (Self : in out Named_Field_Internal) is
   begin
      Free (Self.Operator);
      Free (Self.Value);
   end Free;

   ---------------
   -- To_String --
   ---------------

   function To_String
     (Self : Named_Field_Internal; Long : Boolean) return String
   is
      Result : Unbounded_String;
      C      : Field_List.Cursor;
   begin
      if Self.Value /= null then
         if Self.Table = No_Names then
            Result := To_Unbounded_String (Self.Value.all);

         elsif Long then
            if Self.Table.Instance = null then
               Result := To_Unbounded_String
                 (Self.Table.Name.all & '.' & Self.Value.all);
            else
               Result := To_Unbounded_String
                 (Self.Table.Instance.all & '.' & Self.Value.all);
            end if;
         else
            Result := To_Unbounded_String (Self.Value.all);
         end if;
      end if;

      if Self.Operator /= null then
         C := First (Self.List.List);
         Result := To_Unbounded_String (To_String (Element (C)));
         Next (C);

         while Has_Element (C) loop
            Result := Result & " " & Self.Operator.all & " "
              & To_String (Element (C));
            Next (C);
         end loop;
      end if;

      return To_String (Result);
   end To_String;

   -------------------
   -- Append_Tables --
   -------------------

   procedure Append_Tables
     (Self : Named_Field_Internal; To : in out Table_Sets.Set) is
   begin
      if Self.Table /= No_Names then
         Include (To, Self.Table);
      end if;
   end Append_Tables;

   -----------------------------
   -- Append_If_Not_Aggregate --
   -----------------------------

   procedure Append_If_Not_Aggregate
     (Self         : access Named_Field_Internal;
      To           : in out SQL_Field_List'Class;
      Is_Aggregate : in out Boolean)
   is
      C : Field_List.Cursor := First (Self.List.List);
   begin
      while Has_Element (C) loop
         Append_If_Not_Aggregate (Element (C), To, Is_Aggregate);
         Next (C);
      end loop;

      --  We create a SQL_Field_Text, but it might be any other type.
      --  This isn't really relevant, however, since the exact type is not used
      --  later on.

      if Self.Table /= No_Names then
         Self.Refcount := Self.Refcount + 1;
         Append
           (To.List, Any_Fields.Field'
              (Table    => Self.Table.Name,
               Instance => Self.Table.Instance,
               Name     => null,
               Data     => (Ada.Finalization.Controlled with
                            SQL_Field_Internal_Access (Self))));
      end if;
   end Append_If_Not_Aggregate;

   ------------
   -- Adjust --
   ------------

   procedure Adjust (Self : in out Field_Data) is
   begin
      if Self.Data /= null then
         Self.Data.Refcount := Self.Data.Refcount + 1;
      end if;
   end Adjust;

   --------------
   -- Finalize --
   --------------

   procedure Finalize (Self : in out Field_Data) is
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
        (SQL_Field_Internal'Class, SQL_Field_Internal_Access);
   begin
      if Self.Data /= null then
         Self.Data.Refcount := Self.Data.Refcount - 1;
         if Self.Data.Refcount = 0 then
            Free (Self.Data.all);
            Unchecked_Free (Self.Data);
         end if;
      end if;
   end Finalize;

   ---------
   -- "&" --
   ---------

   function "&" (Left, Right : SQL_Field'Class) return SQL_Field_List is
      Result : SQL_Field_List;
   begin
      Append (Result.List, Left);
      Append (Result.List, Right);
      return Result;
   end "&";

   ---------
   -- "&" --
   ---------

   function "&"
     (Left : SQL_Field_List; Right : SQL_Field'Class) return SQL_Field_List
   is
      Result : SQL_Field_List;
   begin
      Result.List := Left.List;  --  Does a copy, so we do not modify Left
      Append (Result.List, Right);
      return Result;
   end "&";

   ---------
   -- "&" --
   ---------

   function "&"
     (Left : SQL_Field'Class; Right : SQL_Field_List) return SQL_Field_List
   is
      Result : SQL_Field_List;
   begin
      Result.List := Right.List; --  Does a copy so that we do not modify Right
      Prepend (Result.List, Left);
      return Result;
   end "&";

   ---------
   -- "&" --
   ---------

   function "&"
     (Left, Right : SQL_Field_List) return SQL_Field_List
   is
      Result : SQL_Field_List;
      C      : Field_List.Cursor := First (Right.List);
   begin
      Result.List := Left.List; --  Does a copy, don't modify Left
      while Has_Element (C) loop
         Append (Result.List, Element (C));
         Next (C);
      end loop;
      return Result;
   end "&";

   ---------
   -- "+" --
   ---------

   function "+" (Left : SQL_Field'Class) return SQL_Field_List is
      Result : SQL_Field_List;
   begin
      Append (Result.List, Left);
      return Result;
   end "+";

   -------------------
   -- Append_Tables --
   -------------------

   procedure Append_Tables (Self : SQL_Field; To : in out Table_Sets.Set) is
   begin
      if Self.Table /= null then
         Include (To, (Name => Self.Table, Instance => Self.Instance));
      end if;
   end Append_Tables;

   -----------------------------
   -- Append_If_Not_Aggregate --
   -----------------------------

   procedure Append_If_Not_Aggregate
     (Self         : SQL_Field;
      To           : in out SQL_Field_List'Class;
      Is_Aggregate : in out Boolean)
   is
      pragma Unreferenced (Is_Aggregate);
   begin
      --  Ignore constant fields (NULL,...)
      if Self.Table /= null then
         Append (To.List, Self);
      end if;
   end Append_If_Not_Aggregate;

   ---------------
   -- To_String --
   ---------------

   function To_String
     (Self : SQL_Criteria; Long : Boolean := True) return String
   is
   begin
      if Self.Criteria.Data /= null then
         return To_String (Self.Criteria.Data.all, Long);
      else
         return "";
      end if;
   end To_String;

   -------------------
   -- Append_Tables --
   -------------------

   procedure Append_Tables (Self : SQL_Criteria; To : in out Table_Sets.Set) is
   begin
      if Self.Criteria.Data /= null then
         Append_Tables (Self.Criteria.Data.all, To);
      end if;
   end Append_Tables;

   -----------------------------
   -- Append_If_Not_Aggregate --
   -----------------------------

   procedure Append_If_Not_Aggregate
     (Self         : SQL_Criteria;
      To           : in out SQL_Field_List'Class;
      Is_Aggregate : in out Boolean) is
   begin
      if Self.Criteria.Data /= null then
         Append_If_Not_Aggregate (Self.Criteria.Data.all, To, Is_Aggregate);
      end if;
   end Append_If_Not_Aggregate;

   --------------
   -- Set_Data --
   --------------

   procedure Set_Data
     (Self : in out SQL_Criteria; Data : not null access SQL_Criteria_Data) is
   begin
      --  Make sure Adjust/Finalize are properly called for memory management.
      --  We cannot simply change the pointer directly

      Self.Criteria :=
        Controlled_SQL_Criteria'
          (Ada.Finalization.Controlled with
           Data => SQL_Criteria_Data_Access (Data));
   end Set_Data;

   --------------
   -- Get_Data --
   --------------

   function Get_Data (Self : SQL_Criteria) return SQL_Criteria_Data_Access is
   begin
      return Self.Criteria.Data;
   end Get_Data;

   ------------
   -- Adjust --
   ------------

   procedure Adjust (Self : in out Controlled_SQL_Criteria) is
   begin
      if Self.Data /= null then
         Self.Data.Refcount := Self.Data.Refcount + 1;
      end if;
   end Adjust;

   --------------
   -- Finalize --
   --------------

   procedure Finalize (Self : in out Controlled_SQL_Criteria) is
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
        (SQL_Criteria_Data'Class, SQL_Criteria_Data_Access);
   begin
      if Self.Data /= null then
         Self.Data.Refcount := Self.Data.Refcount - 1;
         if Self.Data.Refcount = 0 then
            Free (Self.Data.all);
            Unchecked_Free (Self.Data);
         end if;
      end if;
   end Finalize;

   ------------
   -- Adjust --
   ------------

   procedure Adjust (Self : in out SQL_Field_Pointer) is
   begin
      if Self.Data /= null then
         Self.Data.Refcount := Self.Data.Refcount + 1;
      end if;
   end Adjust;

   --------------
   -- Finalize --
   --------------

   procedure Finalize (Self : in out SQL_Field_Pointer) is
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
        (Field_Pointer_Data, Field_Pointer_Data_Access);
      procedure Unchecked_Free is new Ada.Unchecked_Deallocation
        (SQL_Field'Class, Field_Access);
   begin
      if Self.Data /= null then
         Self.Data.Refcount := Self.Data.Refcount - 1;
         if Self.Data.Refcount = 0 then
            Unchecked_Free (Self.Data.Field);
            Unchecked_Free (Self.Data);
         end if;
      end if;
   end Finalize;

   ---------
   -- "+" --
   ---------

   function "+" (Field : SQL_Field'Class) return SQL_Field_Pointer is
   begin
      return SQL_Field_Pointer'
        (Ada.Finalization.Controlled with
         Data => new Field_Pointer_Data'
           (Refcount => 1,
            Field    => new SQL_Field'Class'(Field)));
   end "+";

   ---------------
   -- To_String --
   ---------------

   overriding function To_String
     (Self : Comparison_Criteria; Long : Boolean := True) return String
   is
      Arg1 : constant String := To_String (Self.Arg1, Long => Long);
      Arg2 : constant String := To_String (Self.Arg2, Long => Long);
   begin
      if Self.Op.all = "="
        and then Arg2 = "TRUE"
      then
         return Arg1;

      elsif Self.Op.all = "="
        and then Arg2 = "FALSE"
      then
         return "not " & Arg1;

      elsif Self.Suffix /= null then
         return Arg1 & Self.Op.all & Arg2 & Self.Suffix.all;

      else
         return Arg1 & Self.Op.all & Arg2;
      end if;
   end To_String;

   -------------------
   -- Append_Tables --
   -------------------

   overriding procedure Append_Tables
     (Self : Comparison_Criteria; To : in out Table_Sets.Set) is
   begin
      Append_Tables (Self.Arg1, To);
      Append_Tables (Self.Arg2, To);
   end Append_Tables;

   -----------------------------
   -- Append_If_Not_Aggregate --
   -----------------------------

   overriding procedure Append_If_Not_Aggregate
     (Self         : Comparison_Criteria;
      To           : in out SQL_Field_List'Class;
      Is_Aggregate : in out Boolean) is
   begin
      Append_If_Not_Aggregate (Self.Arg1, To, Is_Aggregate);
      Append_If_Not_Aggregate (Self.Arg2, To, Is_Aggregate);
   end Append_If_Not_Aggregate;

   -------------
   -- Compare --
   -------------

   function Compare
     (Left, Right : SQL_Field'Class;
      Op          : Cst_String_Access;
      Suffix      : Cst_String_Access := null) return SQL_Criteria
   is
      Data : constant SQL_Criteria_Data_Access :=
        new Comparison_Criteria'
          (SQL_Criteria_Data with
           Op => Op, Suffix => Suffix, Arg1 => +Left, Arg2 => +Right);
      Result : SQL_Criteria;
   begin
      Set_Data (Result, Data);
      return Result;
   end Compare;

   ---------------
   -- To_String --
   ---------------

   function To_String
     (Self : SQL_Field_Pointer; Long : Boolean) return String is
   begin
      return To_String (Self.Data.Field.all, Long);
   end To_String;

   -------------------
   -- Append_Tables --
   -------------------

   procedure Append_Tables
     (Self : SQL_Field_Pointer; To : in out Table_Sets.Set) is
   begin
      if Self.Data /= null and then Self.Data.Field /= null then
         Append_Tables (Self.Data.Field.all, To);
      end if;
   end Append_Tables;

   -----------------------------
   -- Append_If_Not_Aggregate --
   -----------------------------

   procedure Append_If_Not_Aggregate
     (Self         : SQL_Field_Pointer;
      To           : in out SQL_Field_List'Class;
      Is_Aggregate : in out Boolean) is
   begin
      if Self.Data.Field /= null then
         Append_If_Not_Aggregate (Self.Data.Field.all, To, Is_Aggregate);
      end if;
   end Append_If_Not_Aggregate;

   -----------
   -- First --
   -----------

   function First (List : SQL_Field_List) return Field_List.Cursor is
   begin
      return First (List.List);
   end First;

   ------------
   -- Append --
   ------------

   procedure Append
     (List : in out SQL_Field_List'Class; Field : SQL_Field_Pointer) is
   begin
      if Field.Data /= null and then Field.Data.Field /= null then
         Append (List.List, Field.Data.Field.all);
      end if;
   end Append;

   -------------------
   -- Append_Tables --
   -------------------

   procedure Append_Tables
     (Self : SQL_Assignment; To : in out Table_Sets.Set)
   is
      C : Assignment_Lists.Cursor := First (Self.List);
   begin
      while Has_Element (C) loop
         Append_Tables (Element (C).Field, To);
         Append_Tables (Element (C).To_Field, To);
         Next (C);
      end loop;
   end Append_Tables;

   ---------------
   -- To_String --
   ---------------

   function To_String
     (Self : SQL_Assignment; With_Field : Boolean) return String
   is
      Result : Unbounded_String;
      C      : Assignment_Lists.Cursor := First (Self.List);
      Data   : Assignment_Item;
   begin
      while Has_Element (C) loop
         Data := Element (C);
         if Result /= Null_Unbounded_String then
            Append (Result, ", ");
         end if;

         if Data.To_Field /= No_Field_Pointer then
            if With_Field then
               Append
                 (Result, To_String (Data.Field, Long => False)
                  & "=" & To_String (Data.To_Field, Long => True));
            else
               Append (Result, To_String (Data.To_Field, Long => True));
            end if;

         elsif With_Field then
            Append
              (Result, To_String (Data.Field, Long => False)
               & "=" & Null_String);
         else
            Append (Result, Null_String);
         end if;

         Next (C);
      end loop;
      return To_String (Result);
   end To_String;

   -------------
   -- To_List --
   -------------

   procedure To_List (Self : SQL_Assignment; List : out SQL_Field_List) is
      N    : SQL_Field_Internal_Access;
      C    : Assignment_Lists.Cursor := First (Self.List);
      Data : Assignment_Item;
   begin
      while Has_Element (C) loop
         Data := Element (C);

         if Data.To_Field /= No_Field_Pointer then
            Append (List, Data.To_Field);

         else
            --  Setting a field to null
            N := new Named_Field_Internal;
            List := List
              & Any_Fields.Field'
              (Table    => null,
               Instance => null,
               Name     => null,
               Data     => (Ada.Finalization.Controlled with N));
            Named_Field_Internal (N.all).Value := new String'(Null_String);
         end if;

         Next (C);
      end loop;
   end To_List;

   ----------------
   -- Get_Fields --
   ----------------

   procedure Get_Fields (Self : SQL_Assignment; List : out SQL_Field_List) is
      C    : Assignment_Lists.Cursor := First (Self.List);
   begin
      while Has_Element (C) loop
         Append (List, Element (C).Field);
         Next (C);
      end loop;
   end Get_Fields;

   ---------
   -- "&" --
   ---------

   function "&" (Left, Right : SQL_Assignment) return SQL_Assignment is
      Result : SQL_Assignment;
      C      : Assignment_Lists.Cursor := First (Right.List);
   begin
      Result.List := Left.List;
      while Has_Element (C) loop
         Append (Result.List, Element (C));
         Next (C);
      end loop;
      return Result;
   end "&";

   ------------
   -- Assign --
   ------------

   procedure Assign
     (R     : out SQL_Assignment;
      Field : SQL_Field'Class;
      Value : GNAT.Strings.String_Access)
   is
   begin
      if Value = null then
         Append (R.List, Assignment_Item'(+Field, No_Field_Pointer));
      else
         declare
            N : constant SQL_Field_Internal_Access := new Named_Field_Internal;
            A : constant Assignment_Item :=
              (Field    => +Field,
               To_Field => +Any_Fields.Field'
                 (Table    => null,
                  Instance => null,
                  Name     => null,
                  Data     => (Ada.Finalization.Controlled with N)));
         begin
            Named_Field_Internal (N.all).Value := new String'(Value.all);
            Append (R.List, A);
         end;
      end if;
   end Assign;

   -----------------
   -- Field_Types --
   -----------------

   package body Field_Types is

      package Typed_Data_Fields is new Data_Fields (Field);

      function From_Table
        (Table : SQL_Single_Table'Class;
         Name  : Field) return Field'Class
      is
         F : Typed_Data_Fields.Field
           (Table => null, Instance => Table.Instance, Name => null);
         D : constant Named_Field_Internal_Access := new Named_Field_Internal;
      begin
         D.Table := (Name => null, Instance => Table.Instance);
         D.Value := new String'(Name.Name.all);
         F.Data.Data := SQL_Field_Internal_Access (D);
         return F;
      end From_Table;

      ----------------
      -- Expression --
      ----------------

      function Expression (Value : Ada_Type) return Field'Class is
         Data : constant Named_Field_Internal_Access :=
           new Named_Field_Internal;
      begin
         Data.Value := new String'(To_SQL (Value));
         return Typed_Data_Fields.Field'
           (Table => null, Instance => null, Name => null,
            Data => (Ada.Finalization.Controlled with
                     Data => SQL_Field_Internal_Access (Data)));
      end Expression;

      -----------------
      -- From_String --
      -----------------

      function From_String (SQL : String) return Field'Class is
         Data : constant Named_Field_Internal_Access :=
           new Named_Field_Internal;
      begin
         Data.Value := new String'(SQL);
         return Typed_Data_Fields.Field'
           (Table => null, Instance => null, Name => null,
            Data => (Ada.Finalization.Controlled with
                     Data => SQL_Field_Internal_Access (Data)));
      end From_String;

      ---------
      -- "&" --
      ---------

      function "&"
        (Field : SQL_Field'Class; Value : Ada_Type) return SQL_Field_List is
      begin
         return Field & Expression (Value);
      end "&";

      function "&"
        (Value : Ada_Type; Field : SQL_Field'Class) return SQL_Field_List is
      begin
         return Expression (Value) & Field;
      end "&";

      function "&"
        (List : SQL_Field_List; Value : Ada_Type) return SQL_Field_List is
      begin
         return List & Expression (Value);
      end "&";

      function "&"
        (Value : Ada_Type; List : SQL_Field_List) return SQL_Field_List is
      begin
         return Expression (Value) & List;
      end "&";

      --------------
      -- Operator --
      --------------

      function Operator (Field1, Field2 : Field'Class) return Field'Class is
         F : Typed_Data_Fields.Field
           (Table => null, Instance => null, Name => null);
         D : constant Named_Field_Internal_Access := new Named_Field_Internal;
      begin
         D.Operator := new String'(Name);
         D.List := Field1 & Field2;
         F.Data.Data := SQL_Field_Internal_Access (D);
         return F;
      end Operator;

      ---------------------
      -- Scalar_Operator --
      ---------------------

      function Scalar_Operator
        (Self : Field'Class; Operand : Scalar) return Field'Class
      is
         F : Typed_Data_Fields.Field
           (Table => null, Instance => null, Name => null);
         D : constant Named_Field_Internal_Access := new Named_Field_Internal;

         F2 : Typed_Data_Fields.Field
           (Table => null, Instance => null, Name => null);
         D2 : constant Named_Field_Internal_Access :=
           new Named_Field_Internal;

      begin
         D.Operator := new String'(Name);

         D2.Value := new String'(Prefix & Scalar'Image (Operand) & Suffix);
         F2.Data.Data := SQL_Field_Internal_Access (D2);

         D.List := Self & F2;
         F.Data.Data := SQL_Field_Internal_Access (D);
         return F;
      end Scalar_Operator;

      ------------------
      -- SQL_Function --
      ------------------

      function SQL_Function return Field'Class is
         F : Typed_Data_Fields.Field
           (Table => null, Instance => null, Name => null);
         D : constant Named_Field_Internal_Access := new Named_Field_Internal;
      begin
         D.Value := new String'(Name);
         F.Data.Data := SQL_Field_Internal_Access (D);
         return F;
      end SQL_Function;

      --------------------
      -- Apply_Function --
      --------------------

      function Apply_Function
        (Self : Argument_Type'Class) return Field'Class
      is
         F : Typed_Data_Fields.Field
           (Table => null, Instance => null, Name => null);
         D : constant Named_Field_Internal_Access := new Named_Field_Internal;
      begin
         if Suffix /= ")" and then Suffix /= "" then
            D.Value := new String'
              (Name & To_String (Self, Long => True) & " " & Suffix);
         else
            D.Value := new String'
              (Name & To_String (Self, Long => True) & Suffix);
         end if;
         F.Data.Data := SQL_Field_Internal_Access (D);
         return F;
      end Apply_Function;

      ---------------
      -- Operators --
      ---------------

      function "=" (Left : Field; Right : Field'Class) return SQL_Criteria is
      begin
         return Compare (Left, Right, Comparison_Equal'Access);
      end "=";

      function "/=" (Left : Field; Right : Field'Class) return SQL_Criteria is
      begin
         return Compare (Left, Right, Comparison_Different'Access);
      end "/=";

      function "<" (Left : Field; Right : Field'Class) return SQL_Criteria is
      begin
         return Compare (Left, Right, Comparison_Less'Access);
      end "<";

      function "<=" (Left : Field; Right : Field'Class) return SQL_Criteria is
      begin
         return Compare (Left, Right, Comparison_Less_Equal'Access);
      end "<=";

      function ">" (Left : Field; Right : Field'Class) return SQL_Criteria is
      begin
         return Compare (Left, Right, Comparison_Greater'Access);
      end ">";

      function ">=" (Left : Field; Right : Field'Class) return SQL_Criteria is
      begin
         return Compare (Left, Right, Comparison_Greater_Equal'Access);
      end ">=";

      function "=" (Left : Field; Right : Ada_Type) return SQL_Criteria
      is
      begin
         return Compare (Left, Expression (Right), Comparison_Equal'Access);
      end "=";

      function "/=" (Left : Field; Right : Ada_Type) return SQL_Criteria
      is
      begin
         return Compare
           (Left, Expression (Right), Comparison_Different'Access);
      end "/=";

      function "<" (Left : Field; Right : Ada_Type) return SQL_Criteria is
      begin
         return Compare (Left, Expression (Right), Comparison_Less'Access);
      end "<";

      function "<=" (Left : Field; Right : Ada_Type) return SQL_Criteria
      is
      begin
         return Compare
           (Left, Expression (Right), Comparison_Less_Equal'Access);
      end "<=";

      function ">" (Left : Field; Right : Ada_Type) return SQL_Criteria is
      begin
         return Compare
           (Left, Expression (Right), Comparison_Greater'Access);
      end ">";

      function ">=" (Left : Field; Right : Ada_Type) return SQL_Criteria is
      begin
         return Compare
           (Left, Expression (Right), Comparison_Greater_Equal'Access);
      end ">=";

      function Greater_Than
        (Left : SQL_Field'Class; Right : Field) return SQL_Criteria
      is
      begin
         return Compare (Left, Right, Comparison_Greater'Access);
      end Greater_Than;

      function Greater_Or_Equal
        (Left : SQL_Field'Class; Right : Field) return SQL_Criteria
      is
      begin
         return Compare (Left, Right, Comparison_Greater_Equal'Access);
      end Greater_Or_Equal;

      function Equal
        (Left : SQL_Field'Class; Right : Field) return SQL_Criteria
      is
      begin
         return Compare (Left, Right, Comparison_Equal'Access);
      end Equal;

      function Less_Than
        (Left : SQL_Field'Class; Right : Field) return SQL_Criteria
      is
      begin
         return Compare (Left, Right, Comparison_Less'Access);
      end Less_Than;

      function Less_Or_Equal
        (Left : SQL_Field'Class; Right : Field) return SQL_Criteria
      is
      begin
         return Compare (Left, Right, Comparison_Less_Equal'Access);
      end Less_Or_Equal;

      function Greater_Than
        (Left : SQL_Field'Class; Right : Ada_Type) return SQL_Criteria is
      begin
         return Compare
           (Left, Expression (Right), Comparison_Greater'Access);
      end Greater_Than;

      function Greater_Or_Equal
        (Left : SQL_Field'Class; Right : Ada_Type) return SQL_Criteria is
      begin
         return Compare
           (Left, Expression (Right), Comparison_Greater_Equal'Access);
      end Greater_Or_Equal;

      function Equal
        (Left : SQL_Field'Class; Right : Ada_Type) return SQL_Criteria is
      begin
         return Compare (Left, Expression (Right), Comparison_Equal'Access);
      end Equal;

      function Less_Than
        (Left : SQL_Field'Class; Right : Ada_Type) return SQL_Criteria is
      begin
         return Compare
           (Left, Expression (Right), Comparison_Less'Access);
      end Less_Than;

      function Less_Or_Equal
        (Left : SQL_Field'Class; Right : Ada_Type) return SQL_Criteria is
      begin
         return Compare
           (Left, Expression (Right), Comparison_Less_Equal'Access);
      end Less_Or_Equal;

      function "=" (Self : Field; Value : Ada_Type) return SQL_Assignment is
         Result : SQL_Assignment;
      begin
         Assign (Result, Self, new String'(To_SQL (Value)));
         return Result;
      end "=";

      ---------
      -- "=" --
      ---------

      function "=" (Self : Field; To : Field'Class) return SQL_Assignment is
         Result : SQL_Assignment;
      begin
         --  Special case when assigning to one of the Null_Field constants

         if To.Table = null
           and then To.Instance = null
           and then To.Name = Null_String'Access
         then
            Assign (Result, Self, null);

         else
            Append (Result.List, Assignment_Item'(+Self, +To));
         end if;

         return Result;
      end "=";

   end Field_Types;

end GNATCOLL.SQL_Impl;
